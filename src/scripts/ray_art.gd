extends RefCounted
## Original thin sand ray, facing local -Z. Joints are driven by its behaviour.
## All meshes and the three materials are shared; building the art has no side effects.
static var _meshes: Dictionary = {}
static var _skin: StandardMaterial3D
static var _dark: StandardMaterial3D
static var _sand: StandardMaterial3D
const LENGTH := 1.98
const FRONT_Z := -1.08
const WING_PIVOT := 0.29

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "SandRayArt"
	_visual(root, "Body", _body_mesh(), _skin_material())
	for side: int in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "WingLeft" if side < 0 else "WingRight"
		wing.position.x = float(side) * WING_PIVOT
		root.add_child(wing)
		_visual(wing, "Fin", _wing_mesh(side), _skin_material())
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.0, 0.72)
	root.add_child(tail)
	_visual(tail, "Whip", _tail_mesh(), _skin_material())
	_visual(root, "EyesAndSpiracles", _face_mesh(), _dark_material())
	root.set_meta("facing", Vector3.FORWARD)
	root.set_meta("wing_span", 2.8)
	root.set_meta("burial_offset", -0.03)
	root.set_meta("decorative_only", true)
	return root

static func _visual(parent: Node3D, label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result

static func _skin_material() -> StandardMaterial3D:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.vertex_color_use_as_albedo = true
		_skin.roughness = 0.91
		_skin.metallic_specular = 0.14
		_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _skin

static func _dark_material() -> StandardMaterial3D:
	if _dark == null:
		_dark = StandardMaterial3D.new()
		_dark.vertex_color_use_as_albedo = true
		_dark.roughness = 0.40
		_dark.metallic_specular = 0.25
		_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _dark

static func sand_material() -> Material:
	# Duplicate this material per sand patch before fading albedo_color.a.
	if _sand == null:
		_sand = StandardMaterial3D.new()
		_sand.albedo_color = Color(0.61, 0.60, 0.48, 0.94)
		_sand.vertex_color_use_as_albedo = true
		_sand.roughness = 1.0
		_sand.metallic_specular = 0.08
		_sand.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sand.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _sand

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	for index in range(3):
		surface.set_color([ca, cb, cc][index])
		surface.add_vertex([a, b, c][index])

static func _skin_color(point: Vector3, underside: bool = false) -> Color:
	if underside:
		return Color("c8bea0").lerp(Color("b7ad92"), absf(sin(point.x * 5.0 + point.z * 3.0)) * 0.28)
	# Broad, irregular brown freckles remain part of the ray when it swims away.
	var grain: float = sin(point.x * 21.0 + sin(point.z * 12.3) * 2.0) * cos(point.z * 25.0 - point.x * 3.0)
	var mottle: float = smoothstep(0.25, 0.75, grain)
	var broad: float = 0.5 + 0.5 * sin(point.x * 5.1 + point.z * 8.2)
	return Color("bdb193").lerp(Color("827c67"), mottle * 0.54 + broad * 0.10)

static func _half_width(v: float) -> float:
	return 0.39 * pow(maxf(sin(v * PI), 0.0), 0.55)

static func _body_point(v: float, across: float, underside: bool) -> Vector3:
	var envelope: float = maxf(sin(v * PI), 0.0)
	var y: float = (-0.017 - sqrt(maxf(0.0, 1.0 - across * across)) * 0.034) if underside else (0.035 + sqrt(maxf(0.0, 1.0 - across * across)) * 0.060)
	return Vector3(across * _half_width(v), y * envelope, FRONT_Z + v * LENGTH)

static func _body_mesh() -> ArrayMesh:
	if _meshes.has("Body"):
		return _meshes.Body
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for underside: bool in [false, true]:
		for row in range(28):
			for column in range(10):
				var v0: float = float(row) / 28.0
				var v1: float = float(row + 1) / 28.0
				var u0: float = float(column) / 5.0 - 1.0
				var u1: float = float(column + 1) / 5.0 - 1.0
				var a: Vector3 = _body_point(v0, u0, underside)
				var b: Vector3 = _body_point(v1, u0, underside)
				var c: Vector3 = _body_point(v0, u1, underside)
				var d: Vector3 = _body_point(v1, u1, underside)
				_quad(surface, a, b, c, d, underside)
	# Small eyes sit on low skin ridges instead of a second thick body shape.
	for side: float in [-1.0, 1.0]:
		_ellipsoid(surface, Vector3(side * 0.21, 0.097, -0.58), Vector3(0.092, 0.046, 0.12), Color("a89f81"))
		_ellipsoid(surface, Vector3(side * 0.22, 0.079, -0.34), Vector3(0.076, 0.019, 0.090), Color("a49a7d"))
	surface.generate_normals()
	_meshes.Body = surface.commit()
	return _meshes.Body

static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, underside: bool, offset: Vector3 = Vector3.ZERO, reverse: bool = false) -> void:
	var ca: Color = _skin_color(a + offset, underside)
	var cb: Color = _skin_color(b + offset, underside)
	var cc: Color = _skin_color(c + offset, underside)
	var cd: Color = _skin_color(d + offset, underside)
	if underside == reverse:
		_triangle(surface, a, c, b, ca, cc, cb)
		_triangle(surface, c, d, b, cc, cd, cb)
	else:
		_triangle(surface, a, b, c, ca, cb, cc)
		_triangle(surface, c, b, d, cc, cb, cd)

static func _wing_point(v: float, across: float, side: int, underside: bool) -> Vector3:
	var envelope: float = maxf(sin(v * PI), 0.0)
	var outer: float = 1.40 * pow(envelope, 1.35) * (1.0 + 0.035 * sin(v * TAU))
	var inner: float = maxf(0.0, _half_width(v) - 0.025)
	var width: float = lerpf(inner, maxf(outer, inner), across)
	var thickness: float = lerpf(0.035, 0.004, across) * envelope
	var y: float = -thickness * 0.48 if underside else thickness
	# Slightly scalloped trailing edges keep the silhouette soft and organic.
	y += sin(v * PI * 2.0) * across * across * 0.009
	return Vector3(float(side) * (width - WING_PIVOT), y, FRONT_Z + v * LENGTH)

static func _wing_mesh(side: int) -> ArrayMesh:
	var key: String = "Left" if side < 0 else "Right"
	if _meshes.has(key):
		return _meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var offset := Vector3(float(side) * WING_PIVOT, 0, 0)
	for underside: bool in [false, true]:
		for row in range(28):
			for column in range(8):
				var v0: float = float(row) / 28.0
				var v1: float = float(row + 1) / 28.0
				var u0: float = float(column) / 8.0
				var u1: float = float(column + 1) / 8.0
				var a: Vector3 = _wing_point(v0, u0, side, underside)
				var b: Vector3 = _wing_point(v1, u0, side, underside)
				var c: Vector3 = _wing_point(v0, u1, side, underside)
				var d: Vector3 = _wing_point(v1, u1, side, underside)
				_quad(surface, a, b, c, d, underside, offset, side < 0)
	surface.generate_normals()
	_meshes[key] = surface.commit()
	return _meshes[key]

static func _ellipsoid(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	for row in range(6):
		for column in range(12):
			var points: Array[Vector3] = []
			for spec: Vector2i in [Vector2i(row, column), Vector2i(row + 1, column), Vector2i(row, column + 1), Vector2i(row + 1, column + 1)]:
				var lat: float = float(spec.x) * PI / 6.0
				var angle: float = float(spec.y) * TAU / 12.0
				points.append(center + Vector3(cos(angle) * sin(lat), cos(lat), sin(angle) * sin(lat)) * size)
			_triangle(surface, points[0], points[1], points[2], color, color, color)
			_triangle(surface, points[2], points[1], points[3], color, color, color)

static func _face_mesh() -> ArrayMesh:
	if _meshes.has("Face"):
		return _meshes.Face
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		_ellipsoid(surface, Vector3(side * 0.215, 0.133, -0.604), Vector3(0.046, 0.017, 0.061), Color("343c32"))
		_ellipsoid(surface, Vector3(side * 0.215, 0.149, -0.612), Vector3(0.024, 0.003, 0.033), Color("111d1c"))
		_ellipsoid(surface, Vector3(side * 0.206, 0.151, -0.626), Vector3(0.009, 0.002, 0.010), Color("d1ceb1"))
		_ellipsoid(surface, Vector3(side * 0.225, 0.096, -0.325), Vector3(0.033, 0.004, 0.057), Color("5d6552"))
		for gill in range(4):
			var z: float = -0.12 + float(gill) * 0.10
			_triangle(surface, Vector3(side * 0.20, -0.045, z), Vector3(side * 0.29, -0.034, z + 0.018), Vector3(side * 0.20, -0.045, z + 0.017), Color("817e6b"), Color("817e6b"), Color("817e6b"))
	surface.generate_normals()
	_meshes.Face = surface.commit()
	return _meshes.Face

static func _tail_mesh() -> ArrayMesh:
	if _meshes.has("Tail"):
		return _meshes.Tail
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(26):
		var t0: float = float(segment) / 26.0
		var t1: float = float(segment + 1) / 26.0
		for side in range(8):
			var a: float = float(side) * TAU / 8.0
			var b: float = float(side + 1) * TAU / 8.0
			var p: Vector3 = _tail_point(t0, a)
			var q: Vector3 = _tail_point(t1, a)
			var r: Vector3 = _tail_point(t0, b)
			var s: Vector3 = _tail_point(t1, b)
			_quad(surface, p, q, r, s, false, Vector3(0, 0, 0.72), true)
	surface.generate_normals()
	_meshes.Tail = surface.commit()
	return _meshes.Tail

static func _tail_point(t: float, angle: float) -> Vector3:
	var radius: float = lerpf(0.044, 0.005, pow(t, 0.62))
	var center := Vector3(sin(t * 2.2) * t * 0.12, 0.018 * sin(t * PI), t * 2.20)
	return center + Vector3(cos(angle) * radius, sin(angle) * radius * 0.65, 0)

static func sand_cover_mesh() -> ArrayMesh:
	if _meshes.has("SandCover"):
		return _meshes.SandCover
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(64):
		var a: float = float(segment) * TAU / 64.0
		var b: float = float(segment + 1) * TAU / 64.0
		for ring in range(5):
			var t0: float = float(ring) / 5.0
			var t1: float = float(ring + 1) / 5.0
			var p: Vector3 = _sand_point(a, t0)
			var q: Vector3 = _sand_point(b, t0)
			var r: Vector3 = _sand_point(a, t1)
			var s: Vector3 = _sand_point(b, t1)
			var c0 := Color(1, 1, 1, sin(t0 * PI) * 0.82)
			var c1 := Color(1, 1, 1, sin(t1 * PI) * 0.82)
			_triangle(surface, p, q, r, c0, c0, c1)
			_triangle(surface, q, s, r, c0, c1, c1)
	surface.generate_normals()
	_meshes.SandCover = surface.commit()
	return _meshes.SandCover

static func sand_mesh() -> ArrayMesh:
	return sand_cover_mesh()

static func _sand_point(angle: float, t: float) -> Vector3:
	var radial: float = lerpf(0.40, 1.14, t)
	var z: float = cos(angle) * LENGTH * 0.50
	var x: float = sin(angle) * pow(absf(sin(angle)), 0.35) * 1.40
	var uneven: float = 1.0 + sin(angle * 7.0) * 0.025 + cos(angle * 11.0) * 0.014
	return Vector3(x * radial * uneven, 0.012 + sin(t * PI) * 0.034, z * radial * uneven - 0.09)
