class_name CanyonThresherShark
extends Node3D
## A rare local encounter, separate from the ordinary catchable fish population.
const Ocean = preload("res://scripts/ocean_config.gd")
const SPAWN_CHANCE := 0.35
const VIEW_DISTANCE := 185.0
var spawned: bool = false
var spawn_roll: float = 1.0
var phase_offset: float = 0.0
var tail: Node3D
var _world_origin := Vector3.ZERO
static var _meshes: Dictionary = {}
static var _skin: StandardMaterial3D
static var _eyes: StandardMaterial3D

static func build(parent: Node3D) -> Node3D:
	var shark = new()
	shark.name = "CanyonThresherShark"
	parent.add_child(shark)
	shark._world_origin = parent.global_position if parent.is_inside_tree() else parent.position
	shark._assemble()
	shark.visible = false
	shark.set_meta("feature_name", "长尾鲨")
	shark.set_meta("spawn_chance", SPAWN_CHANCE)
	shark.set_meta("ambient_only", true)
	shark.set_meta("no_collision", true)
	shark.set_meta("ordinary_population_unchanged", true)
	return shark

func begin_dive(seed_value: int, force_spawn: bool = false) -> bool:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	spawn_roll = random.randf()
	spawned = force_spawn or spawn_roll < SPAWN_CHANCE
	phase_offset = random.randf_range(-PI, PI)
	position = _route_point(0.0) - _world_origin
	rotation = Vector3.ZERO
	if tail != null:
		tail.rotation = Vector3.ZERO
	visible = false
	return spawned

func animate(time: float, viewer: Vector3) -> void:
	if not spawned:
		visible = false
		return
	var point: Vector3 = _route_point(time)
	var forward: Vector3 = (_route_point(time + 0.1) - point).normalized()
	position = point - _world_origin
	if forward.length_squared() > 0.001:
		basis = Basis.looking_at(forward, Vector3.UP)
	rotation.z = sin(time * 0.45 + phase_offset) * 0.035
	if tail != null:
		tail.rotation.y = sin(time * 2.3 + phase_offset) * 0.16
		tail.rotation.z = sin(time * 1.15 + phase_offset) * 0.035
	visible = viewer.distance_to(point) < VIEW_DISTANCE

func _route_point(time: float) -> Vector3:
	var phase: float = time * 0.038 + phase_offset
	var z: float = Ocean.CANYON_CENTER.z + sin(phase) * 92.0
	var x: float = Ocean.canyon_center_x(z) + sin(phase * 2.0) * 8.0
	return Vector3(x, Ocean.seabed_height(x, z) + 26.0 + sin(phase * 2.0) * 2.0, z)

func _assemble() -> void:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.vertex_color_use_as_albedo = true
		_skin.roughness = 0.48
		_skin.metallic = 0.15
		_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
		_eyes = StandardMaterial3D.new()
		_eyes.albedo_color = Color("172831")
		_eyes.roughness = 0.22
		_eyes.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual(self, "BodyAndFins", _body_mesh(), _skin)
	tail = Node3D.new()
	tail.name = "Tail"
	tail.position.z = 1.52
	add_child(tail)
	_visual(tail, "LongUpperLobe", _tail_mesh(), _skin)
	_visual(self, "EyesAndGills", _eye_mesh(), _eyes)

static func _visual(parent: Node3D, label: String, mesh: Mesh, material: Material) -> void:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.visibility_range_end = VIEW_DISTANCE
	result.visibility_range_end_margin = 15.0
	parent.add_child(result)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(vertex)

static func _body_mesh() -> ArrayMesh:
	if _meshes.has("Body"):
		return _meshes.Body
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := [Vector3(-1.80, 0.015, 0.018), Vector3(-1.55, 0.18, 0.19), Vector3(-1.10, 0.31, 0.32), Vector3(-0.50, 0.39, 0.40), Vector3(0.15, 0.38, 0.43), Vector3(0.75, 0.29, 0.33), Vector3(1.20, 0.15, 0.19), Vector3(1.58, 0.066, 0.09)]
	for row in range(sections.size() - 1):
		for segment in range(20):
			var a: float = float(segment) * TAU / 20.0
			var b: float = float(segment + 1) * TAU / 20.0
			var near: Vector3 = sections[row]
			var far: Vector3 = sections[row + 1]
			var p := Vector3(cos(a) * near.y, sin(a) * near.z, near.x)
			var q := Vector3(cos(b) * near.y, sin(b) * near.z, near.x)
			var r := Vector3(cos(a) * far.y, sin(a) * far.z, far.x)
			var s := Vector3(cos(b) * far.y, sin(b) * far.z, far.x)
			var band: float = smoothstep(-0.18, 0.4, sin((a + b) * 0.5))
			var color: Color = Color("d0d9ce").lerp(Color("4e7486"), band)
			_triangle(surface, p, q, r, color)
			_triangle(surface, q, s, r, color)
	var fin := Color("567889")
	# Long swept pectorals and a compact dorsal distinguish it from a generic fish.
	for side: float in [-1.0, 1.0]:
		_fin(surface, [Vector3(side * 0.28, -0.12, -0.66), Vector3(side * 0.78, -0.23, -0.18), Vector3(side * 1.36, -0.38, 0.62), Vector3(side * 0.56, -0.20, 0.41), Vector3(side * 0.27, -0.14, 0.28)], fin)
		_fin(surface, [Vector3(side * 0.18, -0.15, 0.80), Vector3(side * 0.48, -0.28, 1.25), Vector3(side * 0.15, -0.15, 1.20)], fin)
	_fin(surface, [Vector3(0, 0.35, -0.48), Vector3(0, 1.15, 0.00), Vector3(0, 0.85, 0.12), Vector3(0, 0.29, 0.70)], fin)
	_fin(surface, [Vector3(0, 0.12, 1.16), Vector3(0, 0.35, 1.35), Vector3(0, 0.07, 1.48)], fin)
	surface.generate_normals()
	_meshes.Body = surface.commit()
	return _meshes.Body

static func _fin(surface: SurfaceTool, boundary: Array, color: Color) -> void:
	var normal := Vector3.ZERO
	for index in range(boundary.size()):
		normal += boundary[index].cross(boundary[(index + 1) % boundary.size()])
	var polygon := PackedVector2Array()
	for point: Vector3 in boundary:
		if absf(normal.x) >= maxf(absf(normal.y), absf(normal.z)):
			polygon.append(Vector2(point.z, point.y))
		elif absf(normal.y) >= absf(normal.z):
			polygon.append(Vector2(point.x, point.z))
		else:
			polygon.append(Vector2(point.x, point.y))
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	for index in range(0, indices.size(), 3):
		_triangle(surface, boundary[indices[index]], boundary[indices[index + 1]], boundary[indices[index + 2]], color)

static func _tail_mesh() -> ArrayMesh:
	if _meshes.has("Tail"):
		return _meshes.Tail
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fin := Color("628191")
	# A curved upper lobe longer than the trunk is the thresher's defining silhouette.
	_fin(surface, [Vector3(0, 0, 0), Vector3(0, 0.34, 0.34), Vector3(0, 1.08, 0.96), Vector3(0, 2.13, 2.24), Vector3(0, 2.75, 3.11), Vector3(0, 2.13, 2.67), Vector3(0, 1.03, 1.53), Vector3(0, 0.12, 0.61)], fin)
	_fin(surface, [Vector3(0, 0.05, 0.08), Vector3(0, -0.67, 0.90), Vector3(0, -0.30, 0.75), Vector3(0, 0.08, 0.46)], fin.darkened(0.05))
	surface.generate_normals()
	_meshes.Tail = surface.commit()
	return _meshes.Tail

static func _eye_mesh() -> ArrayMesh:
	if _meshes.has("Eyes"):
		return _meshes.Eyes
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * 0.235, 0.083, -1.36)
		for segment in range(12):
			var a: float = float(segment) * TAU / 12.0
			var b: float = float(segment + 1) * TAU / 12.0
			_triangle(surface, center + Vector3(side * 0.014, 0, 0), center + Vector3(0, cos(a) * 0.060, sin(a) * 0.065), center + Vector3(0, cos(b) * 0.060, sin(b) * 0.065), Color.WHITE)
		for gill in range(5):
			var z: float = -0.93 + float(gill) * 0.09
			var x: float = side * (0.336 + float(gill) * 0.009)
			_triangle(surface, Vector3(x, 0.15, z), Vector3(x + side * 0.008, -0.15, z + 0.04), Vector3(x, -0.14, z + 0.055), Color.WHITE)
	surface.generate_normals()
	_meshes.Eyes = surface.commit()
	return _meshes.Eyes
