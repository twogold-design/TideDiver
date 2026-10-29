class_name OceanArt
extends RefCounted

const Ocean = preload("res://scripts/ocean_config.gd")
const FishArt = preload("res://scripts/fish_art.gd")
const CoralGarden = preload("res://scripts/coral_garden.gd")
const CanyonArt = preload("res://scripts/canyon_art.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const ReefLife = preload("res://scripts/reef_life.gd")
const DiveExpansions = preload("res://scripts/dive_expansions.gd")
static var _reef_coral: ArrayMesh
static var _life_materials: Dictionary = {}

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

static func _rock(parent: Node3D, pos: Vector3, size: Vector3, variant: int = 0) -> MeshInstance3D:
	var stone: MeshInstance3D = _mesh(parent, Geology.rock_mesh(variant), pos, Geology.rock_material())
	# Keep eroded hero rocks within the original collision envelope, including
	# the tops of tall stone spires, rather than leaving an invisible upper cap.
	var bounds: AABB = stone.mesh.get_aabb()
	stone.scale = size * Vector3(2,2,2) / bounds.size
	stone.position = pos - bounds.get_center() * stone.scale
	stone.set_meta("stonefish_rock",true)
	return stone

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
	if _reef_coral == null:
		_reef_coral = CoralGarden._coral_mesh(0)
	var muted: Color = color.lerp(Color("a19b87"),0.42)
	var coral: MeshInstance3D = _mesh(parent, _reef_coral, pos, CoralGarden.material(muted))
	coral.scale = Vector3.ONE * size / 2.1

static func _life_material(color: Color) -> StandardMaterial3D:
	if not _life_materials.has(color):
		var material: StandardMaterial3D = ReefLife.material()
		material.albedo_color = color
		_life_materials[color] = material
	return _life_materials[color]

static func _weed(parent: Node3D, pos: Vector3, size: float, color: Color) -> void:
	if parent.to_global(pos).y+size > -0.5:
		return
	var plant: MeshInstance3D = _mesh(parent, ReefLife.mesh("Seagrass"), pos, _life_material(color))
	plant.scale = Vector3(size*0.45,size/1.5,size*0.45)

static func _reef(parent: Node3D, pos: Vector3, size: float, seed_value: int) -> void:
	_rock(parent, pos - Vector3(0, size * 0.32, 0), Vector3(size, size * 0.48, size * 0.8), seed_value)
	_solid_rock(parent, pos - Vector3(0, size * 0.32, 0), Vector3(size, size * 0.48, size * 0.8))
	var sand_cap: MeshInstance3D = _mesh(parent, Geology.rock_mesh(seed_value+1), pos-Vector3(0,size*0.05,0), Geology.sand_material())
	sand_cap.scale = Vector3(size*0.88,size*0.1,size*0.68)
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
		var sponge: MeshInstance3D = _mesh(parent, ReefLife.mesh("TubeSponge"), p, _life_material(Color("8ba7be") if i % 2 == 0 else Color("dbb4ae")))
		sponge.scale = Vector3.ONE * size * 0.15

static func _water_and_rays(parent: Node3D) -> void:
	var surface_shader: Shader = Shader.new()
	surface_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
uniform float viewer_depth = 0.0;
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
	ALBEDO *= exp(-viewer_depth * 0.012);
	ALPHA = 0.39 + glint * 0.18;
}
"""
	var surface_material: ShaderMaterial = ShaderMaterial.new()
	surface_material.shader = surface_shader
	parent.set_meta("water_surface_material",surface_material)
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
uniform float viewer_depth = 0.0;
void fragment() {
	float silhouette = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float fade = pow(sin(clamp(UV.y, 0.0, 1.0) * 3.14159), 1.5);
	float shimmer = 0.88 + 0.12 * sin(TIME * 0.35 + UV.y * 9.0);
	ALBEDO = vec3(0.52, 0.71, 0.60);
	ALPHA = silhouette * fade * shimmer * 0.024 * exp(-viewer_depth * 0.035);
}
"""
	var ray_material: ShaderMaterial = ShaderMaterial.new()
	ray_material.shader = ray_shader
	parent.set_meta("sunshaft_material",ray_material)
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
	var material: Material = Geology.sand_material()
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
	_rock(parent,anchor,Vector3(4.8,anchor_height+1.0,3.8),3)
	_solid_rock(parent,anchor,Vector3(4.8,anchor_height+1.0,3.8))
	_reef(parent,first,5.3,0)
	# Shallow coral beds sit on low outcrops, never float above the sand.
	for i: int in range(15):
		var a: float = float(i)*2.399
		var distance: float = 22.0+float(i%4)*13.0
		var p: Vector3 = _ground_point(cos(a)*distance,sin(a)*distance)
		var size := Vector3(2.2+float(i%3),1.3,2.0+float(i%2))
		_rock(parent,p+Vector3.UP*0.55,size,i)
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
	Geology.decorate(parent)
	ReefLife.build(parent)
	DiveExpansions.build(parent)

static func create_diver() -> Node3D:
	return preload("res://scripts/diver_art.gd").build()

static func create_fish(kind: int) -> Node3D:
	return FishArt.build(kind)

static func create_pickup(kind: String) -> Node3D:
	var loot_art = preload("res://scripts/loot_art.gd")
	if loot_art.supports(kind):
		return loot_art.build(kind)
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
		var shell: StandardMaterial3D = _life_material(Color("e2c3c4"))
		var lower: MeshInstance3D = _mesh(root, ReefLife.shell_valve_mesh(), Vector3(0,0.1,-0.3),shell)
		lower.rotation.z = PI
		lower.scale = Vector3(0.7,0.7,0.9)
		var lid: MeshInstance3D = _mesh(root, ReefLife.shell_valve_mesh(), Vector3(0,0.13,-0.3),shell)
		lid.scale = Vector3(0.7,0.7,0.9)
		lid.rotation.x = -0.85
		_sphere(root, Vector3(0, 0.30, 0.16), Vector3.ONE * 0.24, _mat(Color("f2ead0"), 0.40), 20)
	return root

static func set_chest_open(node: Node3D, opened: bool = true) -> void:
	preload("res://scripts/loot_art.gd").set_chest_open(node,opened)

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
	var stone: Material = Geology.rock_material()
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

static func _outer_spires(parent: Node3D) -> void:
	# Eroded slabs follow two banks of an open gully; the passage remains clear.
	for i: int in range(8):
		var x: float = -15.0 if i%2 == 0 else 14.0
		var z: float = -22.0+float(i/2)*10.0
		var height: float = 5.0+float(i%3)*3.0
		var p: Vector3 = _region_ground(parent,x,z,height*0.45)
		var size := Vector3(3.4,height*0.65,6.0)
		_rock(parent,p,size,i+2)
		_solid_rock(parent,p,size)
		_weed(parent,p+Vector3.UP*height*0.62,1.7,MINT)

static func _outer_atoll(parent: Node3D) -> void:
	var shell: StandardMaterial3D = _life_material(Color("dec5cf"))
	var pearl: StandardMaterial3D = _mat(Color("e0ecd3"),0.35)
	for i: int in range(12):
		var angle: float = float(i)*TAU/12.0
		var pos: Vector3 = _region_ground(parent,cos(angle)*23.0,sin(angle)*19.0-8,0.3)
		var base: Vector3 = pos-Vector3(0,0,1.0)
		var lower: MeshInstance3D = _mesh(parent,ReefLife.shell_valve_mesh(),base,shell)
		lower.rotation.z = PI
		lower.scale = Vector3(3,0.8,3)
		_sphere(parent,base+Vector3(0,0.7,1.3),Vector3.ONE*0.60,pearl,20)
		var lid: MeshInstance3D = _mesh(parent,ReefLife.shell_valve_mesh(),base+Vector3.UP*0.1,shell)
		lid.scale = Vector3(3,0.9,3)
		lid.rotation.x = -0.65
		_weed(parent,pos+Vector3(3,0,0),2.1,MINT)

static func _set_outer_visibility(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			child.visibility_range_end = maxf(child.visibility_range_end,145.0)
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
				CanyonArt.build(region)
				_outer_gate(region,_region_ground(region,0,-6))
				_outer_gate(region,_region_ground(region,0,-30),0.8)
				for i: int in range(6):
					var p: Vector3 = _region_ground(region,-22+float(i)*8,-17,0.8)
					_box(region,p,Vector3(3,1.6,2.5),_mat(Color("6d898b")))
					_solid_box(region,p,Vector3(3,1.6,2.5))
			"merchant_wreck":
				preload("res://scripts/explorable_wreck.gd").build(region)
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
			if index == 0:
				var world: Vector3 = region.to_global(p)
				var cross_slope: float = absf(Ocean.seabed_height(world.x-2.6,world.z)-Ocean.seabed_height(world.x+2.6,world.z))
				if cross_slope > 4.0:
					continue
			var size := Vector3(2.6,1.5,3.4)
			_rock(region,p,size,i+index)
			_solid_rock(region,p,size)
	# Sparse bottom-dwelling vegetation gives the long routes scale.
	for i: int in range(70):
		var a: float = float(i)*2.399
		var radius: float = 75.0+float(i%13)*39.0
		var p: Vector3 = _ground_point(cos(a)*radius,sin(a)*radius,0.15)
		_weed(outer,p,1.7+float(i%3)*0.8,MINT.darkened(0.12))
	_set_outer_visibility(outer)

