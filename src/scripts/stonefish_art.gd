extends RefCounted
## Original reef stonefish, facing -Z. Body and fins share the neighbouring rock shader.
const Geology = preload("res://scripts/ocean_geology.gd")
static var _meshes: Dictionary = {}
static var _face_material: StandardMaterial3D

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "StonefishArt"
	_visual(root, "RockBody", _body_mesh(), Geology.rock_material())
	_visual(root, "LowEyesAndMouth", _face_mesh(), _dark_material())
	var spines := Node3D.new()
	spines.name = "Spines"
	spines.position.y = 0.32
	root.add_child(spines)
	_visual(spines, "DorsalSpines", _spine_mesh(), Geology.rock_material())
	for side: int in [-1, 1]:
		var fin := Node3D.new()
		fin.name = "PectoralLeft" if side < 0 else "PectoralRight"
		fin.position = Vector3(float(side) * 0.32, 0.045, -0.08)
		root.add_child(fin)
		_visual(fin, "FoldedFan", _pectoral_mesh(side), Geology.rock_material())
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.12, 0.54)
	root.add_child(tail)
	_visual(tail, "ShortTail", _tail_mesh(), Geology.rock_material())
	root.set_meta("facing", Vector3.FORWARD)
	root.set_meta("grounded_art", true)
	root.set_meta("shared_rock_material", true)
	root.set_meta("harpoon_center", Vector3(0,0.25,0))
	root.set_meta("contact_center", Vector3(0,0.25,0))
	root.set_meta("contact_radii", Vector3(0.5,0.25,0.85))
	return root

static func _visual(parent: Node3D, label: String, mesh: Mesh, material: Material) -> void:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)

static func _dark_material() -> StandardMaterial3D:
	if _face_material == null:
		_face_material = StandardMaterial3D.new()
		_face_material.vertex_color_use_as_albedo = true
		_face_material.roughness = 0.76
		_face_material.metallic_specular = 0.15
		_face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _face_material

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(vertex)

static func _body_mesh() -> ArrayMesh:
	if _meshes.has("Body"):
		return _meshes.Body
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A single eroded mass replaces a sleek fish silhouette. Its underside rests
	# at the root and the broad, asymmetric shoulders blend with nearby geology.
	var source: Array = Geology.rock_mesh(5).surface_get_arrays(0)
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	for index: int in indices:
		var p: Vector3 = points[index]
		var point := Vector3(p.x * 0.40, p.y * 0.28 + 0.198, p.z * 0.65 - 0.035)
		point.x *= 1.0 + maxf(0.0, -p.z) * 0.15
		var patch: float = 0.5 + 0.5 * sin(p.x * 11.1 + cos(p.z * 9.3) * 2.2)
		surface.set_color(Color("96927b").lerp(Color("c1b499"), patch * 0.55))
		surface.add_vertex(point)
	# Low brow ridges and a thick, irregular lip sit within the rocky head.
	for side: float in [-1.0, 1.0]:
		_ellipsoid(surface, Vector3(side * 0.185, 0.316, -0.42), Vector3(0.088, 0.033, 0.094), Color("a99f84"))
	_head_pad(surface)
	_lip(surface)
	# Sparse skin nodules break up the shoulders without a stack of body spheres.
	for spec: Vector3 in [Vector3(-0.25,0.32,-0.14), Vector3(0.18,0.34,0.06), Vector3(-0.17,0.34,0.26), Vector3(0.27,0.26,0.22)]:
		_ellipsoid(surface, spec, Vector3(0.05,0.025,0.06), Color("a9a38a"))
	surface.generate_normals()
	_meshes.Body = surface.commit()
	return _meshes.Body

static func _head_pad(surface: SurfaceTool) -> void:
	# The lip grows out of a broad, short snout instead of hovering ahead of the
	# irregular rock silhouette. The front stays open around the recessed slit.
	for index in range(24):
		var a: float = float(index)*TAU/24.0
		var b: float = float(index+1)*TAU/24.0
		var p := Vector3(cos(a)*0.30,0.142+sin(a)*0.14,-0.45)
		var q := Vector3(cos(b)*0.30,0.142+sin(b)*0.14,-0.45)
		var r := Vector3(cos(a)*0.23,0.142+sin(a)*0.08,-0.62)
		var s := Vector3(cos(b)*0.23,0.142+sin(b)*0.08,-0.62)
		_triangle(surface,p,r,q,Color("a69d83"))
		_triangle(surface,q,r,s,Color("a69d83"))
		var inner_a := Vector3(cos(a)*0.19,0.142+sin(a)*0.035,-0.635)
		var inner_b := Vector3(cos(b)*0.19,0.142+sin(b)*0.035,-0.635)
		_triangle(surface,r,inner_a,s,Color("a79d83"))
		_triangle(surface,s,inner_a,inner_b,Color("a79d83"))

static func _lip(surface: SurfaceTool) -> void:
	for segment in range(24):
		var a: float = float(segment) * TAU / 24.0
		var b: float = float(segment + 1) * TAU / 24.0
		for ring in range(6):
			var u: float = float(ring) * TAU / 6.0
			var v: float = float(ring + 1) * TAU / 6.0
			var p: Vector3 = _lip_point(a, u)
			var q: Vector3 = _lip_point(b, u)
			var r: Vector3 = _lip_point(a, v)
			var s: Vector3 = _lip_point(b, v)
			_triangle(surface, p, q, r, Color("aaa086"))
			_triangle(surface, q, s, r, Color("aaa086"))

static func _lip_point(angle: float, ring: float) -> Vector3:
	var thickness: float = 0.025 + sin(angle * 3.0) * 0.003
	return Vector3(cos(angle) * (0.205 + cos(ring) * thickness), 0.142 + sin(angle) * (0.045 + cos(ring) * thickness), -0.630 - sin(ring) * thickness)

static func _face_mesh() -> ArrayMesh:
	if _meshes.has("Face"):
		return _meshes.Face
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The eyes have no bright white surround; the recessed mouth reads as a crack.
	for side: float in [-1.0, 1.0]:
		_ellipsoid(surface, Vector3(side * 0.187, 0.345, -0.433), Vector3(0.037, 0.012, 0.038), Color("6b674e"))
		_ellipsoid(surface, Vector3(side * 0.187, 0.355, -0.442), Vector3(0.019, 0.003, 0.024), Color("202b23"))
	for segment in range(24):
		var a: float = float(segment) * TAU / 24.0
		var b: float = float(segment + 1) * TAU / 24.0
		_triangle(surface, Vector3(0,0.142,-0.642), Vector3(cos(a)*0.190,0.142+sin(a)*0.028,-0.642), Vector3(cos(b)*0.190,0.142+sin(b)*0.028,-0.642), Color("3b4438"))
	surface.generate_normals()
	_meshes.Face = surface.commit()
	return _meshes.Face

static func _spine_mesh() -> ArrayMesh:
	if _meshes.has("Spines"):
		return _meshes.Spines
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(9):
		var z: float = -0.37 + float(index) * 0.095
		var base_y: float = 0.025 + sin(float(index) * 0.58) * 0.027
		var height: float = 0.10 + sin(float(index) * 1.9) * 0.023
		var base := Vector3(sin(float(index)*2.1)*0.015,base_y,z)
		var tip: Vector3 = base + Vector3(0,height,0.035)
		for side in range(5):
			var a: float = float(side)*TAU/5.0
			var b: float = float(side+1)*TAU/5.0
			_triangle(surface,base+Vector3(cos(a)*0.022,0,sin(a)*0.025),tip,base+Vector3(cos(b)*0.022,0,sin(b)*0.025),Color("a79a7a"))
		if index < 8:
			_triangle(surface,base,base+Vector3(0,height*0.58,0.03),base+Vector3(0,0,0.10),Color("8b866e"))
	surface.generate_normals()
	_meshes.Spines = surface.commit()
	return _meshes.Spines

static func _pectoral_mesh(side: int) -> ArrayMesh:
	var key: String = "PectoralLeft" if side < 0 else "PectoralRight"
	if _meshes.has(key):
		return _meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0,0.014,0)
	for index in range(9):
		var a: float = -1.18+float(index)*2.36/9.0
		var b: float = -1.18+float(index+1)*2.36/9.0
		var p := Vector3(float(side)*cos(a)*0.15,0.007+float(index%2)*0.011,sin(a)*0.29+0.06)
		var q := Vector3(float(side)*cos(b)*0.15,0.007+float((index+1)%2)*0.011,sin(b)*0.29+0.06)
		_triangle(surface,center,p,q,Color("a49e82").lerp(Color("7e826b"),float(index%3)*0.14))
		_triangle(surface,center+Vector3(0,-0.02,0),q-Vector3.UP*0.008,p-Vector3.UP*0.008,Color("979379"))
	surface.generate_normals()
	_meshes[key] = surface.commit()
	return _meshes[key]

static func _tail_mesh() -> ArrayMesh:
	if _meshes.has("Tail"):
		return _meshes.Tail
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ellipsoid(surface,Vector3(0,0,0.03),Vector3(0.085,0.072,0.14),Color("a49d82"))
	for index in range(8):
		var a: float = -1.1+float(index)*2.2/8.0
		var b: float = -1.1+float(index+1)*2.2/8.0
		var p := Vector3(0,sin(a)*0.14,0.12+cos(a)*0.21)
		var q := Vector3(0,sin(b)*0.14,0.12+cos(b)*0.21)
		_triangle(surface,Vector3(0.012,0,0.05),p,q,Color("a29b7e"))
		_triangle(surface,Vector3(-0.012,0,0.05),q,p,Color("96917a"))
	surface.generate_normals()
	_meshes.Tail = surface.commit()
	return _meshes.Tail

static func _ellipsoid(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	for row in range(5):
		for column in range(10):
			var points: Array[Vector3] = []
			for spec: Vector2i in [Vector2i(row,column),Vector2i(row+1,column),Vector2i(row,column+1),Vector2i(row+1,column+1)]:
				var lat: float = float(spec.x)*PI/5.0
				var angle: float = float(spec.y)*TAU/10.0
				points.append(center+Vector3(cos(angle)*sin(lat),cos(lat),sin(angle)*sin(lat))*size)
			_triangle(surface,points[0],points[1],points[2],color)
			_triangle(surface,points[2],points[1],points[3],color)
