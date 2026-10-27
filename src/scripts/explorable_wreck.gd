extends Node3D
## A hollow hull: the render mesh itself supplies the collision, including every hole.
const Ocean = preload("res://scripts/ocean_config.gd")
const School = preload("res://scripts/wreck_fish_school.gd")
const SWIM_BOUNDS := AABB(Vector3(-4.0, 1.7, -10.0), Vector3(8.0, 5.9, 20.0))
const INTERIOR_BOUNDS := AABB(Vector3(-5.2, 0.8, -14.3), Vector3(10.4, 7.2, 28.6))
const LOCAL_ENTRANCES := [Vector3(0, 4.7, -15.5), Vector3(0, 4.7, 15.5), Vector3(-6.1, 4.7, 0), Vector3(6.1, 4.7, 0), Vector3(0, 9.2, 0)]
static var _wood: ShaderMaterial
static var _shared_meshes: Dictionary = {}

static func build(parent: Node3D) -> Node3D:
	var root = load("res://scripts/explorable_wreck.gd").new()
	root.name = "ExplorableWreck"
	var parent_origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var world_origin: Vector3 = parent_origin + Vector3(0, 0, -3.0)
	var heading := Basis(Vector3.UP, deg_to_rad(-23.0))
	# Lift the keel above the highest actual triangle under the entire swim space.
	var ground := -INF
	for x in range(-6, 7, 2):
		for z in range(-16, 17, 2):
			var sample: Vector3 = world_origin + heading * Vector3(x, 0, z)
			ground = maxf(ground, Ocean.seabed_height(sample.x, sample.z))
	world_origin.y = ground + 0.45
	root.position = world_origin - parent_origin
	root.basis = heading
	parent.add_child(root)
	root.set_meta("world_transform", Transform3D(heading, world_origin))
	for part: String in ["HullPlanking", "CurvedRibs", "DeckAndCabin"]:
		var mesh: ArrayMesh = _mesh(part)
		var visual := MeshInstance3D.new()
		visual.name = part
		visual.mesh = mesh
		visual.material_override = _material()
		visual.visibility_range_end = 205.0
		visual.visibility_range_end_margin = 22.0
		root.add_child(visual)
		var body := StaticBody3D.new()
		body.name = part + "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var exact: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		exact.backface_collision = true
		shape.shape = exact
		body.add_child(shape)
		root.add_child(body)
	root._build_lower_hull()
	var school: Node3D = School.new()
	school.name = "WreckFishSchool"
	root.add_child(school)
	school.setup(SWIM_BOUNDS)
	var entrances: Array[Vector3] = []
	for entrance: Vector3 in LOCAL_ENTRANCES:
		entrances.append(root._world_position(entrance))
	var route: Array[Vector3] = []
	for z: float in [-18.5, -14.0, -8.0, 0.0, 8.0, 14.0, 18.5]:
		route.append(root._world_position(Vector3(0, 4.7, z)))
	root.set_meta("world_transform", Transform3D(heading, world_origin))
	root.set_meta("entrances", entrances)
	root.set_meta("entrance_names", PackedStringArray(["船首破口", "船尾破口", "左舷破洞", "右舷破洞", "上方舱口"]))
	root.set_meta("interior_center", root._world_position(Vector3(0, 4.7, 0)))
	root.set_meta("interior_bounds", INTERIOR_BOUNDS)
	root.set_meta("local_swim_bounds", SWIM_BOUNDS)
	root.set_meta("safe_swim_route", route)
	root.set_meta("hull_length", 30.0)
	root.set_meta("hull_width", 12.0)
	root.set_meta("interior_clear_height", 8.0)
	root.set_meta("hollow", true)
	root.set_meta("draw_batches", 4 + int(school.get_meta("draw_batches", 2)))
	root.set_meta("collision_matches_mesh", true)
	return root

func contains_point(world: Vector3, margin: float = 2.0) -> bool:
	# The small approach margin lets the following camera shorten before a doorway.
	var current_transform: Transform3D = global_transform if is_inside_tree() else get_meta("world_transform", self.transform)
	return INTERIOR_BOUNDS.grow(margin).has_point(current_transform.affine_inverse() * world)

func _world_position(point: Vector3) -> Vector3:
	var current_transform: Transform3D = global_transform if is_inside_tree() else get_meta("world_transform", self.transform)
	return current_transform * point

func _build_lower_hull() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The buried lower belly follows the slope, so the wreck rests in the sand.
	# Its flat upper surface lies below the hold floor and every swimming route.
	for segment in range(10):
		var z0: float = -15.0 + segment * 3.0
		var z1: float = z0 + 3.0
		var w0: float = _half_width(0.2, z0)
		var w1: float = _half_width(0.2, z1)
		var corners := PackedVector3Array()
		for local: Vector3 in [Vector3(-w0*0.25,0,z0),Vector3(w0*0.25,0,z0),Vector3(w0,0,z0),Vector3(-w0,0,z0),Vector3(-w1*0.25,0,z1),Vector3(w1*0.25,0,z1),Vector3(w1,0,z1),Vector3(-w1,0,z1)]:
			if corners.size() in [0, 1, 4, 5]:
				var world: Vector3 = _world_position(local)
				local.y = minf(-0.25, Ocean.seabed_height(world.x, world.z) - world.y - 0.22)
			corners.append(local)
		_prism(surface, corners, Color("8d927c"))
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var visual := MeshInstance3D.new()
	visual.name = "BuriedLowerHull"
	visual.mesh = mesh
	visual.material_override = _material()
	visual.visibility_range_end = 180.0
	visual.visibility_range_end_margin = 18.0
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "LowerHullCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var exact: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	exact.backface_collision = true
	shape.shape = exact
	body.add_child(shape)
	add_child(body)

static func _mesh(part: String) -> ArrayMesh:
	if _shared_meshes.has(part):
		return _shared_meshes[part]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match part:
		"HullPlanking": _hull(surface)
		"CurvedRibs": _ribs(surface)
		"DeckAndCabin": _deck(surface)
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	_shared_meshes[part] = result
	return result

static func _half_width(y: float, z: float) -> float:
	var beam: float = 3.8 + 2.2 * sin(clampf(y / 8.5, 0.0, 1.0) * PI * 0.65)
	var taper: float = 1.0 - 0.43 * pow(clampf(absf(z) / 15.0, 0.0, 1.0), 3.0)
	return beam * taper

static func _hull(surface: SurfaceTool) -> void:
	var heights := PackedFloat32Array([0.2, 1.35, 2.5, 3.6, 4.7, 5.8, 6.9, 8.1])
	for side: float in [-1.0, 1.0]:
		for band in range(heights.size() - 1):
			for segment in range(10):
				var z0: float = -15.0 + segment * 3.0 + 0.025
				var z1: float = z0 + 2.95
				# Both flanks have a six-metre breach with four metres of headroom.
				if segment in [4, 5] and band in [2, 3, 4, 5]:
					continue
				var y0: float = heights[band] + 0.025
				var y1: float = heights[band + 1] - 0.025
				var a: float = side * _half_width(y0, z0)
				var b: float = side * _half_width(y1, z0)
				var c: float = side * _half_width(y0, z1)
				var d: float = side * _half_width(y1, z1)
				var corners := PackedVector3Array([Vector3(a-0.14,y0,z0), Vector3(a+0.14,y0,z0), Vector3(b+0.14,y1,z0), Vector3(b-0.14,y1,z0), Vector3(c-0.14,y0,z1), Vector3(c+0.14,y0,z1), Vector3(d+0.14,y1,z1), Vector3(d-0.14,y1,z1)])
				_prism(surface, corners, Color("9d987f").lerp(Color("718b83"), float((segment + band) % 4) * 0.13))
	# Narrow floor boards follow the tapered lower hull. The center is never boxed in.
	for segment in range(10):
		var z0: float = -15.0 + segment * 3.0
		var z1: float = z0 + 3.0
		for plank in range(8):
			var left: float = float(plank) / 4.0 - 1.0
			var right: float = float(plank + 1) / 4.0 - 1.0
			var w0: float = _half_width(0.2, z0)
			var w1: float = _half_width(0.2, z1)
			_prism(surface, PackedVector3Array([Vector3(left*w0,0,z0),Vector3(right*w0,0,z0),Vector3(right*w0,0.32,z0),Vector3(left*w0,0.32,z0),Vector3(left*w1,0,z1),Vector3(right*w1,0,z1),Vector3(right*w1,0.32,z1),Vector3(left*w1,0.32,z1)]), Color("929079"))
	_box(surface, Vector3(0, -0.32, 0), Vector3(0.65, 0.9, 30.0), Color("7a7e6d"))

static func _ribs(surface: SurfaceTool) -> void:
	for z: float in [-15.0, -12.0, -9.0, -6.0, -3.2, 3.2, 6.0, 9.0, 12.0, 15.0]:
		for side: float in [-1.0, 1.0]:
			for section in range(8):
				var y0: float = 0.35 + float(section) * 1.0
				var y1: float = y0 + 1.0
				var start := Vector3(side * (_half_width(y0, z) - 0.22), y0, z)
				var finish := Vector3(side * (_half_width(y1, z) - 0.22), y1, z)
				_beam(surface, start, finish, 0.32, 0.38, Color("adb29b"))
	# A few splintered ribs above the deck preserve the wreck's broken silhouette.
	for spec: Vector3 in [Vector3(-5.4,8.3,-6),Vector3(5.0,8.3,9),Vector3(-4.8,8.3,12)]:
		_beam(surface, spec, spec + Vector3(0.25, 1.25, 0.2), 0.25, 0.32, Color("9b9d85"))

static func _deck(surface: SurfaceTool) -> void:
	# Side galleries, plus short end decks, surround one large central hatch.
	for segment in range(10):
		var z0: float = -15.0 + segment * 3.0
		var z1: float = z0 + 2.95
		var w0: float = _half_width(8.2, z0)
		var w1: float = _half_width(8.2, z1)
		for side: float in [-1.0, 1.0]:
			var inner0: float = minf(2.9, w0 - 0.3)
			var inner1: float = minf(2.9, w1 - 0.3)
			var left0: float = -w0 if side < 0 else inner0
			var right0: float = -inner0 if side < 0 else w0
			var left1: float = -w1 if side < 0 else inner1
			var right1: float = -inner1 if side < 0 else w1
			_prism(surface, PackedVector3Array([Vector3(left0,8.25,z0),Vector3(right0,8.25,z0),Vector3(right0,8.58,z0),Vector3(left0,8.58,z0),Vector3(left1,8.25,z1),Vector3(right1,8.25,z1),Vector3(right1,8.58,z1),Vector3(left1,8.58,z1)]), Color("a6a48c"))
		if segment not in [3, 4, 5, 6]:
			_box(surface, Vector3(0, 8.42, (z0 + z1) * 0.5), Vector3(minf(w0,w1)*2.0, 0.33, z1-z0), Color("9b9f89"))
	for side: float in [-1.0, 1.0]:
		_box(surface, Vector3(side * 2.95, 8.72, 0), Vector3(0.22, 0.4, 11.8), Color("b8b69b"))
	# A ruined stern cabin is an open frame above the main through corridor.
	for side: float in [-1.0, 1.0]:
		for z: float in [7.8, 11.8]:
			_box(surface, Vector3(side * 2.2, 9.9, z), Vector3(0.32, 2.6, 0.35), Color("a1a48c"))
		_box(surface, Vector3(side * 2.2, 10.8, 9.8), Vector3(0.22, 0.55, 4.4), Color("a2a58c"))
		for z: float in [8.1, 8.9, 11.2, 11.7]:
			_box(surface, Vector3(side * 2.25, 9.15, z), Vector3(0.14, 0.9, 0.55), Color("7c8b7d"))
	for z: float in [7.8, 11.8]:
		_box(surface, Vector3(0, 11.1, z), Vector3(4.7, 0.3, 0.45), Color("a7aa91"))
	_box(surface, Vector3(-0.4,11.25,10.0),Vector3(3.9,0.22,3.4),Color("909b86"))
	# The broken mast rises from a side gallery, away from the interior fish volume.
	_beam(surface, Vector3(-4.4, 8.4, -6.2), Vector3(-5.1, 16.3, -6.0), 0.45, 0.45, Color("a2a58a"))
	_beam(surface, Vector3(-8.3, 13.6, -6.1), Vector3(-1.6, 13.4, -6.1), 0.24, 0.24, Color("a9ac91"))
	_beam(surface, Vector3(5.4,8.6,-10),Vector3(8.2,8.1,-7.8),0.23,0.23,Color("989d85"))

static func _beam(surface: SurfaceTool, start: Vector3, finish: Vector3, width: float, depth: float, tint: Color) -> void:
	var direction: Vector3 = (finish - start).normalized()
	var right: Vector3 = direction.cross(Vector3.FORWARD if absf(direction.z) < 0.9 else Vector3.UP).normalized() * width * 0.5
	var front: Vector3 = direction.cross(right).normalized() * depth * 0.5
	_prism(surface, PackedVector3Array([start-right-front,start+right-front,finish+right-front,finish-right-front,start-right+front,start+right+front,finish+right+front,finish-right+front]), tint)

static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, tint: Color) -> void:
	var corners := PackedVector3Array()
	for offset: Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:
		corners.append(center + offset * size * 0.5)
	_prism(surface, corners, tint)

static func _prism(surface: SurfaceTool, corners: PackedVector3Array, tint: Color) -> void:
	for face: Array in [[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]]:
		for index: int in [face[0],face[2],face[1],face[0],face[3],face[2]]:
			surface.set_color(tint)
			surface.add_vertex(corners[index])

static func _material() -> ShaderMaterial:
	if _wood != null:
		return _wood
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 timber_position;
varying vec3 timber_normal;
void vertex() {
    timber_position = VERTEX;
    timber_normal = NORMAL;
}
void fragment() {
    float grain = sin(timber_position.z * 28.0 + sin(timber_position.y * 7.3 + timber_position.x * 9.0) * 1.8);
    float endgrain = sin(timber_position.x * 39.0 + timber_position.y * 1.1);
    float scars = pow(abs(sin(timber_position.z * 2.6 + timber_position.x * 3.1)), 24.0);
    float inward = 1.0 - smoothstep(-0.2, 0.2, timber_normal.x * sign(timber_position.x));
    float enclosed = mix(inward, 1.0 - smoothstep(-0.2, 0.2, timber_normal.y), abs(timber_normal.y));
    vec3 weathered = mix(vec3(0.23,0.27,0.23), vec3(0.47,0.45,0.32), 0.52 + grain * 0.065 + endgrain * 0.035);
    weathered *= COLOR.rgb * (1.0 - scars * 0.12);
    ALBEDO = weathered * mix(1.0, 0.48, enclosed);
    ROUGHNESS = 0.96;
    SPECULAR = 0.12;
}
"""
	_wood = ShaderMaterial.new()
	_wood.shader = shader
	return _wood
