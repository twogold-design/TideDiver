class_name OceanArt
extends RefCounted

const Ocean = preload("res://scripts/ocean_config.gd")
const FishArt = preload("res://scripts/fish_art.gd")
const CoralGarden = preload("res://scripts/coral_garden.gd")

const CORAL: Color = Color("ef9277")
const MINT: Color = Color("69c6a4")

static func _mat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.84
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

static func _mesh(parent: Node3D, shape: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
	return instance

static func _sphere(parent: Node3D, pos: Vector3, size: Vector3, material: Material, segments: int = 10) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = 5
	var instance: MeshInstance3D = _mesh(parent, mesh, pos, material)
	instance.scale = size
	return instance

static func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, pos, material)

static func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0 else top_radius
	mesh.height = height
	mesh.radial_segments = 8
	return _mesh(parent, mesh, pos, material)

static func _solid_box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = pos
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

static func _solid_rock(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = pos
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	var points: PackedVector3Array = PackedVector3Array()
	points.append(Vector3(0, size.y, 0))
	points.append(Vector3(0, -size.y, 0))
	for ring: int in range(3):
		var height: float = float(ring - 1) * 0.62
		var width: float = sqrt(1.0 - height * height)
		for i: int in range(10):
			var angle: float = float(i) * TAU / 10.0
			points.append(Vector3(cos(angle) * size.x * width, height * size.y, sin(angle) * size.z * width))
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
static func _branch(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var stem: MeshInstance3D = _cylinder(parent, (start + end) * 0.5, radius, start.distance_to(end), material, radius * 0.65)
	var direction: Vector3 = (end - start).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		stem.quaternion = Quaternion(Vector3.UP, direction)
	_sphere(parent, end, Vector3.ONE * radius * 0.76, material, 8)

static func _coral(parent: Node3D, pos: Vector3, size: float, color: Color) -> void:
	var group: Node3D = Node3D.new()
	group.position = pos
	parent.add_child(group)
	var mat: StandardMaterial3D = _mat(color)
	for i: int in range(5):
		var angle: float = float(i) * TAU / 5.0
		var middle: Vector3 = Vector3(cos(angle) * size * 0.23, size * 0.6, sin(angle) * size * 0.23)
		var tip: Vector3 = Vector3(cos(angle) * size * 0.43, size * (0.85 + sin(float(i) * 3.0) * 0.2), sin(angle) * size * 0.43)
		_branch(group, Vector3.ZERO, middle, size * 0.065, mat)
		_branch(group, middle, tip, size * 0.052, mat)
		_branch(group, middle, middle + Vector3(cos(angle + 1) * size * 0.3, size * 0.2, sin(angle + 1) * size * 0.3), size * 0.038, mat)

static func _weed(parent: Node3D, pos: Vector3, size: float, color: Color) -> void:
	var mat: StandardMaterial3D = _mat(color)
	for i: int in range(4):
		var angle: float = float(i) * 1.9
		var offset: Vector3 = Vector3(cos(angle) * 0.25, 0, sin(angle) * 0.25)
		var leaf: MeshInstance3D = _sphere(parent, pos + offset + Vector3(0, size * 0.45, 0), Vector3(size * 0.08, size * 0.5, size * 0.018), mat, 6)
		leaf.rotation = Vector3(0.16 * cos(angle), angle, 0.17 * sin(angle))

static func _reef(parent: Node3D, pos: Vector3, size: float, seed_value: int) -> void:
	var stone: StandardMaterial3D = _mat(Color("2d686b"))
	var sand: StandardMaterial3D = _mat(Color("8aaf9b"))
	_sphere(parent, pos - Vector3(0, size * 0.32, 0), Vector3(size, size * 0.48, size * 0.8), stone, 9)
	_solid_rock(parent, pos - Vector3(0, size * 0.32, 0), Vector3(size, size * 0.48, size * 0.8))
	_sphere(parent, pos - Vector3(0, size * 0.05, 0), Vector3(size * 0.88, size * 0.1, size * 0.68), sand, 10)
	for i: int in range(7):
		var a: float = float(i) * 2.399 + float(seed_value)
		var distance: float = size * (0.27 + float(i % 3) * 0.19)
		var p: Vector3 = pos + Vector3(cos(a) * distance, 0, sin(a) * distance * 0.7)
		if i % 3 == 0:
			_coral(parent, p, size * (0.34 + float(i % 2) * 0.15), CORAL if i % 2 == 0 else Color("e8bd78"))
		else:
			_weed(parent, p, size * (0.35 + float(i % 3) * 0.12), MINT.darkened(float(i % 3) * 0.09))
	for i: int in range(4):
		var p: Vector3 = pos + Vector3(sin(float(i) * 2.1) * size * 0.7, 0.2, cos(float(i) * 2.1) * size * 0.6)
		_sphere(parent, p, Vector3.ONE * size * 0.12, _mat(Color("7b9dc0") if i % 2 == 0 else Color("d9a0a1")), 7)

static func _water_and_rays(parent: Node3D) -> void:
	var surface_shader: Shader = Shader.new()
	surface_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
varying vec3 world_pos;
void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.24 + TIME * 0.65) * 0.07 + cos(VERTEX.z * 0.31 - TIME * 0.42) * 0.05;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float wave_a = sin(world_pos.x * 0.72 + sin(world_pos.z * 0.31 + TIME * 0.24) * 1.2 + TIME * 0.45);
	float wave_b = cos(world_pos.z * 0.64 + sin(world_pos.x * 0.23 - TIME * 0.16) * 1.3);
	float glint = smoothstep(1.45, 1.9, wave_a + wave_b);
	float broad = 0.5 + 0.5 * sin(world_pos.x * 0.09 + world_pos.z * 0.05 + TIME * 0.06);
	ALBEDO = mix(vec3(0.11, 0.40, 0.46), vec3(0.31, 0.66, 0.64), broad) + vec3(0.35, 0.32, 0.20) * glint;
	ALPHA = 0.39 + glint * 0.18;
}
"""
	var surface_material: ShaderMaterial = ShaderMaterial.new()
	surface_material.shader = surface_shader
	var surface_mesh: PlaneMesh = PlaneMesh.new()
	surface_mesh.size = Ocean.SURFACE_SIZE
	surface_mesh.subdivide_width = 48
	surface_mesh.subdivide_depth = 52
	var surface: MeshInstance3D = _mesh(parent, surface_mesh, Vector3(0, 0.6, 0), surface_material)
	surface.name = "LivingWaterSurface"
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ray_shader: Shader = Shader.new()
	ray_shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
void fragment() {
	float silhouette = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float fade = pow(sin(clamp(UV.y, 0.0, 1.0) * 3.14159), 1.5);
	float shimmer = 0.88 + 0.12 * sin(TIME * 0.35 + UV.y * 9.0);
	ALBEDO = vec3(0.52, 0.71, 0.60);
	ALPHA = silhouette * fade * shimmer * 0.024;
}
"""
	var ray_material: ShaderMaterial = ShaderMaterial.new()
	ray_material.shader = ray_shader
	var ray_positions: Array[Vector3] = [Vector3(-20, -18, -10), Vector3(19, -21, -24), Vector3(-1, -19, -38), Vector3(29, -16, 10), Vector3(-35, -19, 25)]
	for i: int in range(ray_positions.size()):
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 1.2
		cone.bottom_radius = 4.0 + float(i % 2)
		cone.height = 38.0
		cone.radial_segments = 24
		cone.cap_bottom = false
		cone.cap_top = false
		var ray: MeshInstance3D = _mesh(parent, cone, ray_positions[i], ray_material)
		ray.rotation.z = -0.12
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
static func _build_seabed(parent: Node3D) -> void:
	var terrain := Node3D.new()
	terrain.name = "NaturalSeabed"
	parent.add_child(terrain)
	var material: StandardMaterial3D = _mat(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 49 chunks keep distant geometry out of the renderer. Each collision surface
	# uses exactly the same four-metre vertices as Ocean.seabed_height().
	var side: int = 50
	for cz: int in range(7):
		for cx: int in range(7):
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			var indices := PackedInt32Array()
			var origin := Vector3(-Ocean.TERRAIN_EXTENT+float(cx)*200.0,0,-Ocean.TERRAIN_EXTENT+float(cz)*200.0)
			for iz: int in range(side+1):
				for ix: int in range(side+1):
					var x: float = origin.x+float(ix)*Ocean.TERRAIN_STEP
					var z: float = origin.z+float(iz)*Ocean.TERRAIN_STEP
					var h: float = Ocean.terrain_vertex_height(x,z)
					vertices.append(Vector3(float(ix)*Ocean.TERRAIN_STEP,h,float(iz)*Ocean.TERRAIN_STEP))
					var dx: float = Ocean.terrain_vertex_height(x+1.0,z)-Ocean.terrain_vertex_height(x-1.0,z)
					var dz: float = Ocean.terrain_vertex_height(x,z+1.0)-Ocean.terrain_vertex_height(x,z-1.0)
					normals.append(Vector3(-dx,2.0,-dz).normalized())
					var sand_mix: float = clampf(0.68+sin(x*0.06+z*0.04)*0.13+h*0.003,0.0,1.0)
					colors.append(Color("325b67").lerp(Color("a1af91"),sand_mix))
			for iz: int in range(side):
				for ix: int in range(side):
					var a: int = iz*(side+1)+ix
					var b: int = a+1
					var c: int = a+side+1
					var d: int = c+1
					indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var visual: MeshInstance3D = _mesh(terrain,mesh,origin,material)
			visual.name = "Shelf_%d_%d" % [cx,cz]
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.visibility_range_end = 330.0
			visual.visibility_range_end_margin = 25.0
			var body := StaticBody3D.new()
			body.name = "TerrainCollision"
			var collision := CollisionShape3D.new()
			var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
			shape.backface_collision = true
			collision.shape = shape
			visual.add_child(body)
			body.add_child(collision)

static func _ground_point(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x,Ocean.seabed_height(x,z)+lift,z)

static func build_world(parent: Node3D) -> void:
	_water_and_rays(parent)
	_build_seabed(parent)
	# Keep the authored tutorial reef obstruction, anchored into the real shelf.
	var first := Vector3(8,-11,-2)
	var ground: float = Ocean.seabed_height(first.x,first.z)
	var anchor_height: float = (-14.0-ground)*0.5
	var anchor := Vector3(8,ground+anchor_height,-2)
	_sphere(parent,anchor,Vector3(4.8,anchor_height+1.0,3.8),_mat(Color("355e63")),9)
	_solid_rock(parent,anchor,Vector3(4.8,anchor_height+1.0,3.8))
	_reef(parent,first,5.3,0)
	# Shallow coral beds sit on low outcrops, never float above the sand.
	for i: int in range(15):
		var a: float = float(i)*2.399
		var distance: float = 22.0+float(i%4)*13.0
		var p: Vector3 = _ground_point(cos(a)*distance,sin(a)*distance)
		var size := Vector3(2.2+float(i%3),1.3,2.0+float(i%2))
		_sphere(parent,p+Vector3.UP*0.55,size,_mat(Color("426b68")),8)
		_solid_rock(parent,p+Vector3.UP*0.55,size)
		if i%2 == 0:
			_coral(parent,p+Vector3.UP*1.7,2.4,CORAL)
		else:
			_weed(parent,p+Vector3.UP*1.5,3.2,MINT)
	# Familiar small ruins remain discoverable near the departure bay.
	_outer_gate(parent,_ground_point(0,-31),0.58)
	var wreck := Node3D.new()
	wreck.position = _ground_point(36,10)
	wreck.scale = Vector3.ONE*0.5
	parent.add_child(wreck)
	_outer_wreck(wreck)
	var particle_mat: StandardMaterial3D = _mat(Color("83c6b8"),0.25)
	for i: int in range(55):
		var p := Vector3(sin(float(i)*71.3)*55,-3-fposmod(float(i)*7.73,21),cos(float(i)*39.9)*55)
		_sphere(parent,p,Vector3.ONE*0.035,particle_mat,4)
	_build_outer_ocean(parent)

static func create_diver() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "DiverArt"
	var orange: StandardMaterial3D = _mat(Color("ef9257"))
	var dark: StandardMaterial3D = _mat(Color("163644"))
	var yellow: StandardMaterial3D = _mat(Color("f2c958"))
	var skin: StandardMaterial3D = _mat(Color("e4b68d"))
	var glass: StandardMaterial3D = _mat(Color("7fd8df"), 0.15)
	# A streamlined horizontal swimming silhouette, facing local -Z.
	_sphere(root, Vector3(0, 0, 0), Vector3(0.42, 0.28, 0.66), orange)
	_sphere(root, Vector3(0, 0.02, -0.78), Vector3(0.33, 0.31, 0.34), dark)
	_sphere(root, Vector3(0, 0.01, -0.96), Vector3(0.25, 0.23, 0.16), skin)
	_box(root, Vector3(0, 0.10, -1.075), Vector3(0.48, 0.23, 0.09), dark)
	_box(root, Vector3(0, 0.11, -1.13), Vector3(0.40, 0.14, 0.04), glass)
	_box(root, Vector3(-0.10, 0.14, -1.155), Vector3(0.09, 0.035, 0.012), _mat(Color("d8f1de"), 0.2))
	var tank: MeshInstance3D = _cylinder(root, Vector3(0, 0.35, 0.04), 0.22, 0.95, yellow)
	tank.rotation.x = PI / 2
	_box(root, Vector3(0, 0.37, -0.04), Vector3(0.49, 0.42, 0.12), dark)
	_cylinder(root, Vector3(0, 0.35, -0.48), 0.07, 0.16, _mat(Color("adc8b3")))
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = Node3D.new()
		leg.name = "LegLeft" if side < 0 else "LegRight"
		leg.position = Vector3(side * 0.23, 0, 0.47)
		root.add_child(leg)
		_sphere(leg, Vector3(0, 0, 0.43), Vector3(0.16, 0.15, 0.50), dark)
		_sphere(leg, Vector3(0, -0.03, 1.02), Vector3(0.24, 0.055, 0.37), yellow, 6)
		_branch(root, Vector3(side * 0.34, -0.04, -0.28), Vector3(side * 0.58, -0.20, -0.80), 0.115, orange)
		_sphere(root, Vector3(side * 0.58, -0.20, -0.86), Vector3.ONE * 0.12, skin)
	var gun: MeshInstance3D = _cylinder(root, Vector3(0.58, -0.18, -1.1), 0.065, 0.95, dark)
	gun.rotation.x = PI / 2
	var spear: MeshInstance3D = _cylinder(root, Vector3(0.58, -0.15, -1.5), 0.018, 0.7, _mat(Color("d0d9be")))
	spear.rotation.x = PI / 2
	return root

static func create_fish(kind: int) -> Node3D:
	return FishArt.build(kind)

static func create_pickup(kind: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "PickupArt"
	var gold: StandardMaterial3D = _mat(Color("edc77e"))
	if kind == "chest" or kind == "treasure":
		var wood: StandardMaterial3D = _mat(Color("986c4e"))
		_box(root, Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 1.0), wood)
		_sphere(root, Vector3(0, 0.8, 0), Vector3(0.77, 0.4, 0.51), wood, 8)
		for x: float in [-0.52, 0.52]:
			_box(root, Vector3(x, 0.46, -0.515), Vector3(0.12, 0.88, 0.04), gold)
			_box(root, Vector3(x, 1.0, 0), Vector3(0.12, 0.08, 0.96), gold)
		_box(root, Vector3(0, 0.65, -0.54), Vector3(0.22, 0.28, 0.08), gold)
	elif kind == "oxygen" or kind == "air":
		_cylinder(root, Vector3(0, 0.7, 0), 0.33, 1.25, _mat(Color("9acdb6")))
		_cylinder(root, Vector3(0, 1.4, 0), 0.12, 0.22, gold)
		_cylinder(root, Vector3(0, 0.7, 0), 0.34, 0.35, _mat(Color("f0dfb1")))
		_box(root, Vector3(0, 0.7, -0.345), Vector3(0.07, 0.24, 0.03), _mat(Color("387974")))
		_box(root, Vector3(0, 0.7, -0.35), Vector3(0.22, 0.07, 0.03), _mat(Color("387974")))
	else:
		var shell: StandardMaterial3D = _mat(Color("c994a2"))
		_sphere(root, Vector3(0, 0.1, 0), Vector3(0.65, 0.13, 0.55), shell, 10)
		var lid: MeshInstance3D = _sphere(root, Vector3(0, 0.40, 0.3), Vector3(0.64, 0.10, 0.55), shell, 10)
		lid.rotation.x = -0.85
		_sphere(root, Vector3(0, 0.35, -0.1), Vector3.ONE * 0.28, _mat(Color("f2ead0"), 0.55), 12)
	return root

static func create_boat() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "BoatArt"
	var wood: StandardMaterial3D = _mat(Color("bd805a"))
	var cream: StandardMaterial3D = _mat(Color("e9d7a9"))
	var green: StandardMaterial3D = _mat(Color("4b9f94"))
	_sphere(root, Vector3(0, 0.4, 0), Vector3(2.5, 0.9, 5), wood, 10)
	_box(root, Vector3(0, 0.9, 0), Vector3(4.3, 0.2, 7.4), cream)
	for side: float in [-1.0, 1.0]:
		_box(root, Vector3(side * 2.12, 1.25, 0), Vector3(0.18, 0.6, 7.4), wood)
		for z: float in [-2.0, 2.0]:
			_cylinder(root, Vector3(side * 1.8, 2.2, z), 0.08, 2.6, cream)
	_box(root, Vector3(0, 3.55, 0), Vector3(4.5, 0.17, 5), cream)
	for i: int in range(5):
		_box(root, Vector3(-1.9 + float(i) * 0.9, 3.65, 0), Vector3(0.42, 0.05, 5), green)
	_box(root, Vector3(-0.7, 1.45, -1), Vector3(1.4, 0.9, 1.3), green)
	_box(root, Vector3(-0.7, 1.95, -1), Vector3(1.5, 0.14, 1.4), cream)
	for z: float in [-0.5, 0.5]:
		_cylinder(root, Vector3(2.5, -0.5, z), 0.055, 3.7, cream)
	for i: int in range(7):
		var rung: MeshInstance3D = _cylinder(root, Vector3(2.5, 1 - float(i) * 0.5, 0), 0.05, 1.0, cream)
		rung.rotation.x = PI / 2
	return root




static func _outer_gate(parent: Node3D, origin: Vector3, scale_factor: float = 1.0) -> void:
	var root := Node3D.new()
	root.position = origin
	root.scale = Vector3.ONE*scale_factor
	parent.add_child(root)
	var stone: StandardMaterial3D = _mat(Color("729497"))
	var light: StandardMaterial3D = _mat(Color("88d3c5"),0.45)
	for side: float in [-1.0,1.0]:
		_box(root,Vector3(side*7.0,7.0,0),Vector3(3,14,3.5),stone)
		_solid_box(root,Vector3(side*7.0,7.0,0),Vector3(3,14,3.5))
		for y: float in [2.0,7.0,12.0]:
			_box(root,Vector3(side*7.0,y,0),Vector3(3.5,0.6,4),stone)
	_box(root,Vector3(0,14.5,0),Vector3(18,2.3,4),stone)
	_solid_box(root,Vector3(0,14.5,0),Vector3(18,2.3,4))
	for i: int in range(5):
		var glyph := _box(root,Vector3(float(i-2)*2.3,14.5,2.03),Vector3(0.6,0.8,0.12),light)
		glyph.rotation.z = PI*0.25

static func _outer_wreck(parent: Node3D) -> void:
	var hull := Node3D.new()
	hull.position = _region_ground(parent,0,-3,0.8)
	hull.rotation_degrees = Vector3(0,-23,4)
	parent.add_child(hull)
	var wood: StandardMaterial3D = _mat(Color("735747"))
	var bronze: StandardMaterial3D = _mat(Color("bba578"))
	_box(hull,Vector3.ZERO,Vector3(10,0.8,24),wood)
	_solid_box(hull,Vector3.ZERO,Vector3(10,0.8,24))
	for side: float in [-1.0,1.0]:
		for i: int in range(8):
			var rib := _box(hull,Vector3(side*4.7,2.3,float(i-4)*2.8),Vector3(0.45,5.0,0.55),wood)
			rib.rotation.z = side*0.18
		_box(hull,Vector3(side*4.5,3.8,0),Vector3(0.45,0.65,24),wood)
		_solid_box(hull,Vector3(side*4.6,2.0,0),Vector3(0.8,4.0,23))
	var mast := _cylinder(hull,Vector3(0,9,-2),0.3,18,bronze)
	mast.rotation.z = -0.10
	var yard := _cylinder(hull,Vector3(-0.8,14,-2),0.16,12,wood)
	yard.rotation.z = PI*0.5
	_box(hull,Vector3(0,3,7),Vector3(6,5,5),wood)
	_solid_box(hull,Vector3(0,3,7),Vector3(6,5,5))
	for x: float in [-1.6,1.6]:
		_box(hull,Vector3(x,4,4.45),Vector3(1.2,1.3,0.12),_mat(Color("416f79"),0.2))

static func _region_ground(region: Node3D, x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x,Ocean.seabed_height(region.position.x+x,region.position.z+z)-region.position.y+lift,z)

static func _outer_garden(parent: Node3D) -> void:
	var stem: StandardMaterial3D = _mat(Color("365b73"))
	var light: StandardMaterial3D = _mat(Color("63cbd5"),0.75)
	for i: int in range(22):
		var angle: float = float(i)*2.399
		var radius: float = 7.0+float(i%5)*4.5
		var p: Vector3 = _region_ground(parent,cos(angle)*radius,sin(angle)*radius-7)
		var height: float = 2.5+float(i%5)*1.4
		_branch(parent,p,p+Vector3(sin(angle)*1.8,height,cos(angle)*1.4),0.14,stem)
		_sphere(parent,p+Vector3(sin(angle)*1.8,height,cos(angle)*1.4),Vector3(0.6,1.15,0.6),light,7)
		_weed(parent,p,3.4,Color("4a8398"))

static func _outer_spires(parent: Node3D) -> void:
	var stone: StandardMaterial3D = _mat(Color("455e67"))
	# Eroded slabs follow two banks of an open gully; the passage remains clear.
	for i: int in range(8):
		var x: float = -15.0 if i%2 == 0 else 14.0
		var z: float = -22.0+float(i/2)*10.0
		var height: float = 5.0+float(i%3)*3.0
		var p: Vector3 = _region_ground(parent,x,z,height*0.45)
		var size := Vector3(3.4,height*0.65,6.0)
		_sphere(parent,p,size,stone,7)
		_solid_rock(parent,p,size)
		_weed(parent,p+Vector3.UP*height*0.62,1.7,MINT)

static func _outer_atoll(parent: Node3D) -> void:
	var shell: StandardMaterial3D = _mat(Color("c49caa"))
	var pearl: StandardMaterial3D = _mat(Color("e0ecd3"),0.35)
	for i: int in range(12):
		var angle: float = float(i)*TAU/12.0
		var pos: Vector3 = _region_ground(parent,cos(angle)*23.0,sin(angle)*19.0-8,0.3)
		_sphere(parent,pos,Vector3(2.8,0.45,2.0),shell,8)
		_sphere(parent,pos+Vector3.UP*0.7,Vector3.ONE*0.65,pearl,8)
		var lid: MeshInstance3D = _sphere(parent,pos+Vector3(0,1.4,0.8),Vector3(2.7,0.3,1.9),shell,8)
		lid.rotation.x = -0.65
		_weed(parent,pos+Vector3(3,0,0),2.1,MINT)

static func _set_outer_visibility(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			child.visibility_range_end = 145.0
			child.visibility_range_end_margin = 15.0
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_outer_visibility(child)

static func _build_outer_ocean(parent: Node3D) -> void:
	var outer := Node3D.new()
	outer.name = "OuterOcean"
	parent.add_child(outer)
	for index: int in range(Ocean.ZONES.size()):
		var zone: Dictionary = Ocean.ZONES[index]
		var region := Node3D.new()
		region.name = str(zone.id)
		region.position = Vector3(zone.center.x,0,zone.center.z)
		region.set_meta("zone_name",zone.name)
		outer.add_child(region)
		match str(zone.id):
			"twin_gates":
				_outer_gate(region,_region_ground(region,0,-6))
				_outer_gate(region,_region_ground(region,0,-30),0.8)
				for i: int in range(6):
					var p: Vector3 = _region_ground(region,-22+float(i)*8,-17,0.8)
					_box(region,p,Vector3(3,1.6,2.5),_mat(Color("6d898b")))
					_solid_box(region,p,Vector3(3,1.6,2.5))
			"lantern_garden":
				_outer_garden(region)
			"merchant_wreck":
				_outer_wreck(region)
				for i: int in range(7):
					var p: Vector3 = _region_ground(region,-19+float(i)*6,-20,0.3)
					var plank: MeshInstance3D = _box(region,p,Vector3(1.0,0.3,4.5),_mat(Color("80624c")))
					plank.rotation.y = float(i)*0.7
			"amber_reef":
				CoralGarden.build(region)
			"southern_spires":
				_outer_spires(region)
			"pearl_atoll":
				_outer_atoll(region)
		# Low peripheral stones blend the landmark into its natural shelf.
		for i: int in range(4):
			var p: Vector3 = _region_ground(region,-27+float(i)*18,-25,0.65)
			var size := Vector3(2.6,1.5,3.4)
			_sphere(region,p,size,_mat(Color("466968")),8)
			_solid_rock(region,p,size)
	# Sparse bottom-dwelling vegetation gives the long routes scale.
	for i: int in range(70):
		var a: float = float(i)*2.399
		var radius: float = 75.0+float(i%13)*39.0
		var p: Vector3 = _ground_point(cos(a)*radius,sin(a)*radius,0.15)
		_weed(outer,p,1.7+float(i%3)*0.8,MINT.darkened(0.12))
	_set_outer_visibility(outer)

