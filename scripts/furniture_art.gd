class_name FurnitureArt
extends RefCounted
## Shared furniture models for the restaurant and live shop previews.
## build() returns an origin-centred model. The caller applies layout transforms.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _surface_shader: Shader
static var _rug_shader: Shader
static var _font: SystemFont

const CREAM: Color = Color("d8cdb4")
const DARK: Color = Color("334b49")
const BRASS: Color = Color("a68950")

static func _shader() -> Shader:
	if _surface_shader != null:
		return _surface_shader
	_surface_shader = Shader.new()
	_surface_shader.code = """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.6, 0.5, 0.4, 1.0);
uniform int surface_kind = 0;
uniform float roughness_value = 0.75;
uniform float metallic_value = 0.0;
varying vec3 model_pos;
void vertex() { model_pos = VERTEX; }
void fragment() {
	vec3 p = model_pos;
	vec3 color = base_color.rgb;
	if (surface_kind == 1) {
		float warp = sin(p.z * 3.1 + p.y * 1.6) * 1.5 + sin(p.z * 9.2) * 0.2;
		float grain = sin(p.x * 35.0 + warp) / (1.0 + fwidth(p.x) * 70.0);
		float broad = sin(p.x * 12.0 + sin(p.z * 2.1) * 1.1);
		color *= 0.96 + grain * 0.016 + broad * 0.018;
	} else if (surface_kind == 2) {
		float weave = sin(p.x * 145.0) * sin((p.z + p.y) * 145.0) / (1.0 + length(fwidth(p)) * 120.0);
		color *= 0.96 + weave * 0.035;
	} else if (surface_kind == 3) {
		float flow = p.x * 5.1 + p.z * 3.5 + sin(p.z * 4.7) * 0.5 + sin(p.x * 14.0) * 0.1;
		float vein = smoothstep(0.94, 0.995, abs(sin(flow)));
		float cloud = sin(p.x * 1.8 + p.z * 2.7) * 0.025;
		color = color * (0.97 + cloud) - vec3(0.13, 0.12, 0.10) * vein;
	}
	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.32;
}
"""
	return _surface_shader

static func _mat(color: Color, kind: int = 0, roughness: float = 0.75, metal: float = 0.0) -> ShaderMaterial:
	var key: String = "%s:%d:%.2f:%.2f" % [color.to_html(), kind, roughness, metal]
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _shader()
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("roughness_value", roughness)
	material.set_shader_parameter("metallic_value", metal)
	_materials[key] = material
	return material

static func _glass(color: Color) -> StandardMaterial3D:
	var key: String = "glass:" + color.to_html()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.20)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.18
	material.metallic = 0.12
	_materials[key] = material
	return material

static func _glow(color: Color) -> StandardMaterial3D:
	var key: String = "glow:" + color.to_html()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.30
	material.roughness = 0.55
	_materials[key] = material
	return material

static func _mesh(parent: Node3D, shape: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.position = pos
	parent.add_child(node)
	return node

static func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, bevel: float = 0.025) -> MeshInstance3D:
	var radius: float = minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.4)
	var key: String = "box:%s:%.3f" % [str(size), radius]
	var mesh: Mesh
	if _meshes.has(key):
		mesh = _meshes[key] as Mesh
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		box.subdivide_width = 3
		box.subdivide_height = 3
		box.subdivide_depth = 3
		var arrays: Array = box.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var inner: Vector3 = size * 0.5 - Vector3.ONE * radius
		for i: int in range(vertices.size()):
			var core: Vector3 = vertices[i].clamp(-inner, inner)
			var direction: Vector3 = (vertices[i] - core).normalized()
			vertices[i] = core + direction * radius
			normals[i] = direction
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var rounded: ArrayMesh = ArrayMesh.new()
		rounded.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh = rounded
		_meshes[key] = mesh
	return _mesh(parent, mesh, pos, material)

static func _sphere(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var key: String = "sphere"
	if not _meshes.has(key):
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 24
		sphere.rings = 12
		_meshes[key] = sphere
	var node: MeshInstance3D = _mesh(parent, _meshes[key] as Mesh, pos, material)
	node.scale = size
	return node

static func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, top: float = -1.0) -> MeshInstance3D:
	var top_radius: float = radius if top < 0 else top
	var key: String = "cyl:%.3f:%.3f:%.3f" % [radius, height, top_radius]
	if not _meshes.has(key):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = top_radius
		mesh.height = height
		mesh.radial_segments = 32
		_meshes[key] = mesh
	return _mesh(parent, _meshes[key] as Mesh, pos, material)

static func _ring(parent: Node3D, pos: Vector3, radius: float, thickness: float, material: Material) -> MeshInstance3D:
	var key: String = "ring:%.3f:%.3f" % [radius, thickness]
	if not _meshes.has(key):
		var mesh: TorusMesh = TorusMesh.new()
		mesh.inner_radius = radius - thickness
		mesh.outer_radius = radius + thickness
		mesh.rings = 32
		mesh.ring_segments = 8
		_meshes[key] = mesh
	return _mesh(parent, _meshes[key] as Mesh, pos, material)

static func _bar(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = _cylinder(parent, (start + end) * 0.5, radius, start.distance_to(end), material)
	var direction: Vector3 = (end - start).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		node.quaternion = Quaternion(Vector3.UP, direction)
	return node

static func _merge_geometry(root: Node3D) -> void:
	# Merge static parts by material: most complete models use only 4–8 draws.
	var batches: Dictionary = {}
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			var part: MeshInstance3D = child as MeshInstance3D
			var material: Material = part.material_override
			if not batches.has(material):
				batches[material] = []
			batches[material].append(part)
	for material: Variant in batches:
		var parts: Array = batches[material]
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for value: Variant in parts:
			var part: MeshInstance3D = value as MeshInstance3D
			surface.append_from(part.mesh, 0, part.transform)
		var merged: ArrayMesh = surface.commit()
		_mesh(root, merged, Vector3.ZERO, material as Material)
		for value: Variant in parts:
			var part: MeshInstance3D = value as MeshInstance3D
			root.remove_child(part)
			part.free()

static func build(item: Dictionary, seat: int = -1) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Furniture_%d" % int(item.get("uid", -1))
	var kind: String = str(item.get("kind", "table"))
	var variant: String = str(item.get("variant", "basic"))
	if variant not in ["basic", "comfort", "premium"]:
		variant = "basic"
	var palette: Array[Color] = [Color("b68c61"), Color("729d90"), Color("be7f6b")]
	var tint: Color = palette[clampi(int(item.get("color", 0)), 0, 2)]
	root.set_meta("kind", kind)
	root.set_meta("variant", variant)
	root.set_meta("uid", int(item.get("uid", -1)))
	match kind:
		"table": _table(root, variant, tint)
		"plant": _plant(root, variant, tint)
		"rug": _rug(root, variant, tint)
		"lamp": _lamp(root, variant, tint)
		"shelf": _shelf(root, variant, tint)
		"bench": _bench(root, variant, tint)
		"parasol": _parasol(root, variant, tint)
		"coastal": _coastal(root, variant, tint)
	_merge_geometry(root)
	if kind == "table" and seat >= 0:
		_table_number(root, seat)
	return root

static func _bench(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint,1)
	var fabric := _mat(CREAM,2)
	for x: float in [-0.85,0.85]:
		_box(root,Vector3(x,0.3,0),Vector3(0.14,0.6,0.7),wood)
	for z: float in [-0.28,0.0,0.28]:
		_box(root,Vector3(0,0.62,z),Vector3(2.2,0.10,0.23),wood)
	for y: float in [0.85,1.1]:
		_box(root,Vector3(0,y,0.38),Vector3(2.2,0.17,0.10),wood)
	if variant != "basic":
		_box(root,Vector3(0,0.73,0),Vector3(2.05,0.16,0.70),fabric,0.06)
		for x: float in [-0.72,0.72]:
			var pillow := _box(root,Vector3(x,0.96,0.22),Vector3(0.44,0.40,0.15),_mat(tint,2),0.07)
			pillow.rotation.z = x*0.12
	if variant == "premium":
		for i in range(16):
			var x: float = -1.05+i*0.14
			_bar(root,Vector3(x,0.68,0.35),Vector3(x,1.32-absf(x)*0.15,0.40),0.022,_mat(BRASS,1))

static func _parasol(root: Node3D, variant: String, tint: Color) -> void:
	var metal := _mat(BRASS,0,0.35,0.5)
	_cylinder(root,Vector3(0,0.08,0),0.4,0.16,_mat(DARK,3))
	_cylinder(root,Vector3(0,1.4,0),0.045,2.8,metal)
	for i in range(12):
		var a: float = i*TAU/12
		var b: float = (i+1)*TAU/12
		var edge_a := Vector3(cos(a)*1.33,2.28,sin(a)*1.33)
		var edge_b := Vector3(cos(b)*1.33,2.28,sin(b)*1.33)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex: Vector3 in [Vector3(0,2.85,0),edge_a,edge_b,edge_b,edge_a,Vector3(0,2.85,0)]:
			surface.add_vertex(vertex)
		surface.generate_normals()
		var color: Color = CREAM if i%2 == 0 else (Color("365d73") if variant == "premium" else tint)
		_mesh(root,surface.commit(),Vector3.ZERO,_mat(color,2))
		_bar(root,Vector3(0,2.8,0),edge_a,0.015,metal)
		if variant == "comfort":
			for j in range(4):
				var point := edge_a.lerp(edge_b,j/4.0)
				_bar(root,point,point-Vector3.UP*0.16,0.014,_mat(CREAM,2))
		elif variant == "premium":
			_sphere(root,edge_a-Vector3.UP*0.08,Vector3.ONE*0.055,_glow(Color("ffe1a4")))

static func _coastal(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint,1)
	if variant == "basic":
		_box(root,Vector3(0,0.25,0),Vector3(1.0,0.5,0.8),wood)
		for i in range(5):
			_sphere(root,Vector3(-0.34+i*0.17,0.54,sin(i)*0.22),Vector3(0.13,0.06,0.16),_mat(CREAM))
		_cylinder(root,Vector3(0.32,0.73,0.18),0.10,0.45,_glass(Color("6ba89c")))
	elif variant == "comfort":
		_cylinder(root,Vector3(0,0.48,0),0.44,0.92,wood,0.38)
		for y: float in [0.18,0.70]:
			_ring(root,Vector3(0,y,0),0.44,0.028,_mat(DARK,0,0.4,0.6))
		for i in range(3):
			_sphere(root,Vector3(-0.26+i*0.25,1.04,0),Vector3(0.16,0.30,0.16),_mat(Color("cf7751") if i%2 == 0 else CREAM))
	else:
		_box(root,Vector3(0,0.40,0),Vector3(1.05,0.8,0.85),wood)
		_box(root,Vector3(0,1.18,0),Vector3(1.04,0.75,0.84),_glass(Color("77c8ce")))
		_box(root,Vector3(0,0.86,0),Vector3(0.96,0.08,0.77),_mat(CREAM,3))
		for i in range(5):
			var x: float = -0.30+i*0.15
			_bar(root,Vector3(x,0.9,0),Vector3(x+0.08,1.1+i%3*0.14,0.1),0.045,_mat(Color("c9826d")))
		_box(root,Vector3(0,1.59,0),Vector3(1.1,0.08,0.90),_mat(DARK))

static func _table_number(parent: Node3D, seat: int) -> void:
	_box(parent, Vector3(0.40, 1.46, 0.52), Vector3(0.25, 0.25, 0.035), _mat(CREAM))
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	var label: Label3D = Label3D.new()
	label.font = _font
	label.text = str(seat + 1)
	label.font_size = 30
	label.pixel_size = 0.005
	label.position = Vector3(0.40, 1.46, 0.55)
	label.modulate = DARK
	label.outline_size = 0
	parent.add_child(label)

static func _table(root: Node3D, variant: String, tint: Color) -> void:
	var wood: Material = _mat(tint, 1, 0.66)
	var dark_wood: Material = _mat(tint.darkened(0.26), 1, 0.65)
	var brass: Material = _mat(BRASS, 0, 0.34, 0.7)
	var fabric: Material = _mat(tint.lightened(0.15), 2, 0.94)
	if variant == "basic":
		_cylinder(root, Vector3(0, 1.27, 0), 1.04, 0.13, wood)
		_ring(root, Vector3(0, 1.25, 0), 1.015, 0.03, dark_wood)
		for angle: float in [0.3, 2.394, 4.489]:
			_bar(root, Vector3(cos(angle) * 0.48, 1.2, sin(angle) * 0.48), Vector3(cos(angle) * 0.69, 0.09, sin(angle) * 0.69), 0.075, dark_wood)
	elif variant == "comfort":
		_box(root, Vector3(0, 1.27, 0), Vector3(2.15, 0.16, 1.75), wood, 0.075)
		_box(root, Vector3(0, 1.12, 0), Vector3(1.84, 0.17, 1.46), dark_wood)
		for x: float in [-0.83, 0.83]:
			for z: float in [-0.59, 0.59]:
				_bar(root, Vector3(x, 1.13, z), Vector3(x * 1.06, 0.1, z * 1.06), 0.07, dark_wood)
		_box(root, Vector3(0, 1.365, 0), Vector3(0.42, 0.018, 1.65), _mat(tint.lightened(0.30), 2, 0.97), 0.006)
	else:
		var top: Material = _mat(Color("a4aaa1"), 3, 0.43)
		var slab: MeshInstance3D = _cylinder(root, Vector3(0, 1.29, 0), 1.06, 0.11, top)
		slab.scale.z = 0.87
		var rim: MeshInstance3D = _ring(root, Vector3(0, 1.25, 0), 1.04, 0.025, brass)
		rim.scale.z = 0.87
		_cylinder(root, Vector3(0, 0.66, 0), 0.37, 1.13, _mat(tint.darkened(0.35), 1, 0.48), 0.27)
		for i: int in range(16):
			var a: float = float(i) * TAU / 16.0
			_bar(root, Vector3(cos(a) * 0.35, 0.14, sin(a) * 0.35), Vector3(cos(a) * 0.27, 1.19, sin(a) * 0.27), 0.012, brass)
		_cylinder(root, Vector3(0, 0.10, 0), 0.55, 0.08, brass)
	for side: float in [-1.0, 1.0]:
		var z: float = side * 1.40
		if variant == "basic":
			_box(root, Vector3(0, 0.71, z), Vector3(0.86, 0.11, 0.76), wood, 0.04)
			for x: float in [-0.32, 0.0, 0.32]:
				_bar(root, Vector3(x, 0.77, z + side * 0.31), Vector3(x, 1.48, z + side * 0.34), 0.035, dark_wood)
			_box(root, Vector3(0, 1.48, z + side * 0.34), Vector3(0.88, 0.15, 0.12), wood, 0.04)
		else:
			_box(root, Vector3(0, 0.65, z), Vector3(0.90, 0.12, 0.78), dark_wood, 0.04)
			_box(root, Vector3(0, 0.76, z), Vector3(0.84, 0.16, 0.72), fabric, 0.075)
			var back: MeshInstance3D = _box(root, Vector3(0, 1.26, z + side * 0.31), Vector3(0.88, 0.78, 0.16), fabric, 0.07)
			back.rotation.x = side * 0.10
			if variant == "premium":
				for x: float in [-0.24, 0.24]:
					_sphere(root, Vector3(x, 1.30, z + side * 0.20), Vector3.ONE * 0.028, brass)
		for x: float in [-0.31, 0.31]:
			for offset: float in [-0.25, 0.25]:
				_bar(root, Vector3(x, 0.66, z + offset), Vector3(x * 1.08, 0.08, z + offset * 1.1), 0.035 if variant == "premium" else 0.045, brass if variant == "premium" else dark_wood)
	_cylinder(root, Vector3(-0.42, 1.43, 0.48), 0.09, 0.19, _mat(CREAM, 0, 0.35))
	_cylinder(root, Vector3(0.38, 1.46, -0.22), 0.085, 0.24, _mat(tint.darkened(0.10), 0, 0.3))
	for i: int in range(3):
		_sphere(root, Vector3(0.38 + float(i - 1) * 0.045, 1.66, -0.22), Vector3(0.075, 0.11, 0.06), _mat(Color("6a8f67")))

static func _leaf(parent: Node3D, center: Vector3, size: Vector2, angle: float, material: Material, split: bool) -> void:
	if not split:
		var leaf: MeshInstance3D = _sphere(parent, center, Vector3(size.x, 0.018, size.y), material)
		leaf.rotation = Vector3(-0.30, angle, 0.12)
		return
	# A single triangulated, lobed monstera leaf has real silhouette splits.
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline: Array[Vector3] = []
	for i: int in range(28):
		var a: float = float(i) * TAU / 28.0
		var cut: float = 0.64 if i % 4 == 1 else 1.0
		outline.append(Vector3(cos(a) * size.x * cut, 0.025 * cos(a * 2.0), sin(a) * size.y * cut))
	for i: int in range(outline.size()):
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(0.5, 0.5))
		surface.add_vertex(Vector3(0, 0.035, 0))
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2.ZERO)
		surface.add_vertex(outline[(i + 1) % outline.size()])
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2.ONE)
		surface.add_vertex(outline[i])
	var leaf: MeshInstance3D = _mesh(parent, surface.commit(), center, material)
	leaf.rotation = Vector3(-0.45, angle, 0)

static func _plant(root: Node3D, variant: String, tint: Color) -> void:
	var leaf_dark: Material = _mat(Color("416f50"), 0, 0.73)
	var leaf_light: Material = _mat(Color("739264"), 0, 0.68)
	var soil: Material = _mat(Color("514738"))
	if variant == "basic":
		var clay: Material = _mat(tint, 0, 0.88)
		_cylinder(root, Vector3(0, 0.27, 0), 0.22, 0.48, clay, 0.31)
		_ring(root, Vector3(0, 0.50, 0), 0.29, 0.03, clay)
		_cylinder(root, Vector3(0, 0.49, 0), 0.27, 0.015, soil)
		for i: int in range(7):
			var a: float = float(i) * 2.399
			var top: Vector3 = Vector3(cos(a) * 0.16, 0.85 + float(i % 3) * 0.17, sin(a) * 0.16)
			_bar(root, Vector3(0, 0.48, 0), top, 0.012, leaf_dark)
			_leaf(root, top, Vector2(0.07, 0.20), a, leaf_dark if i % 2 else leaf_light, false)
	elif variant == "comfort":
		var ceramic: Material = _mat(tint.lightened(0.12), 0, 0.24)
		_sphere(root, Vector3(0, 0.32, 0), Vector3(0.31, 0.30, 0.31), ceramic)
		_cylinder(root, Vector3(0, 0.12, 0), 0.24, 0.16, ceramic)
		_ring(root, Vector3(0, 0.55, 0), 0.23, 0.035, ceramic)
		_cylinder(root, Vector3(0, 0.55, 0), 0.22, 0.025, soil)
		for i: int in range(5):
			var a: float = float(i) * 2.399
			var tip: Vector3 = Vector3(cos(a) * 0.13, 0.95 + float(i % 3) * 0.24, sin(a) * 0.13)
			_bar(root, Vector3(0, 0.54, 0), tip, 0.018, leaf_dark)
			_leaf(root, tip, Vector2(0.20, 0.24), a, leaf_dark if i % 2 else leaf_light, true)
	else:
		var brass: Material = _mat(BRASS, 0, 0.32, 0.70)
		_box(root, Vector3(0, 0.19, 0), Vector3(0.66, 0.24, 0.48), brass, 0.09)
		_box(root, Vector3(0, 0.315, 0), Vector3(0.54, 0.015, 0.36), soil)
		for x: float in [-0.22, 0.22]:
			_sphere(root, Vector3(x, 0.07, 0), Vector3(0.09, 0.07, 0.16), brass)
		var bark: Material = _mat(Color("775c42"), 1)
		_bar(root, Vector3(-0.09, 0.30, 0), Vector3(0.07, 0.78, 0), 0.055, bark)
		_bar(root, Vector3(0.07, 0.78, 0), Vector3(-0.11, 1.20, 0.05), 0.037, bark)
		for i: int in range(4):
			var p: Vector3 = Vector3(-0.15 + float(i % 2) * 0.30, 0.79 + float(i) * 0.14, float(i % 2) * 0.13 - 0.06)
			_bar(root, Vector3(0, p.y - 0.13, 0), p, 0.025, bark)
			_sphere(root, p, Vector3(0.22, 0.11, 0.20), leaf_dark if i % 2 else leaf_light)

static func _rug_material(variant: String, tint: Color) -> ShaderMaterial:
	var key: String = "rug:" + variant + tint.to_html()
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	if _rug_shader == null:
		_rug_shader = Shader.new()
		_rug_shader.code = """
shader_type spatial;
uniform vec4 base_color : source_color;
uniform int pattern_kind = 0;
varying vec3 rug_pos;
void vertex() { rug_pos = VERTEX; }
void fragment() {
	vec2 uv = rug_pos.xz / vec2(2.8,3.2) + 0.5;
	vec2 p = (uv - 0.5) * 2.0;
	float edge = max(abs(p.x),abs(p.y));
	float weave = sin(rug_pos.x * 230.0) * sin(rug_pos.z * 200.0) / (1.0 + length(fwidth(rug_pos.xz)) * 180.0);
	vec3 color = base_color.rgb * (0.95 + 0.035 * weave);
	vec3 cream = vec3(0.73,0.64,0.46);
	vec3 dark = base_color.rgb * 0.46;
	if (pattern_kind == 0) {
		float stripe = step(0.83,abs(p.y)) * (1.0-step(0.91,abs(p.y)));
		color = mix(color, cream, stripe * 0.75);
	} else if (pattern_kind == 1) {
		float diamond = abs(p.x) + abs(p.y);
		float lines = 1.0-smoothstep(0.025,0.05,abs(fract(diamond*2.0)-0.5));
		color = mix(color,base_color.rgb*0.70,lines*0.38);
		color = mix(color,cream,step(0.89,edge)*0.55);
	} else {
		float border = step(0.70,edge) * (1.0-step(0.91,edge));
		color = mix(color,dark,border);
		float diamonds = abs(fract(uv.x*12.0)-0.5) + abs(fract(uv.y*14.0)-0.5);
		color = mix(color,cream,border * (1.0-step(0.28,diamonds)));
		float r = length(p * vec2(1.10,1.0));
		float petal = 0.26 + 0.055*cos(atan(p.y,p.x)*8.0);
		float medallion = 1.0-smoothstep(petal,petal+0.018,r);
		color = mix(color,cream,medallion);
		color = mix(color,dark,(1.0-step(0.11,abs(p.x)+abs(p.y))));
		float corner = step(0.78,abs(p.x)+abs(p.y))*(1.0-step(0.67,edge));
		color = mix(color,cream,corner*0.55);
		float piping = (step(0.68,edge)-step(0.70,edge))+(step(0.91,edge)-step(0.93,edge));
		color = mix(color,cream,piping);
	}
	ALBEDO = color;
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _rug_shader
	material.set_shader_parameter("base_color", tint)
	material.set_shader_parameter("pattern_kind", 0 if variant == "basic" else (1 if variant == "comfort" else 2))
	_materials[key] = material
	return material

static func _rug(root: Node3D, variant: String, tint: Color) -> void:
	var thickness: float = 0.025 if variant == "basic" else (0.095 if variant == "comfort" else 0.045)
	var material: Material = _rug_material(variant, tint.lightened(0.20) if variant == "comfort" else tint.darkened(0.12))
	_box(root, Vector3(0, 0.065 + thickness * 0.5, 0), Vector3(2.8, thickness, 3.12 if variant == "premium" else 3.2), material, 0.06)
	if variant == "comfort":
		var trim: Material = _mat(tint.lightened(0.32), 2, 0.98)
		for side: float in [-1.0, 1.0]:
			_box(root, Vector3(side * 1.35, 0.13, 0), Vector3(0.08, 0.045, 3.12), trim, 0.02)
			_box(root, Vector3(0, 0.13, side * 1.55), Vector3(2.68, 0.045, 0.08), trim, 0.02)
	elif variant == "premium":
		var fringe: Material = _mat(CREAM, 2, 0.97)
		for side: float in [-1.0, 1.0]:
			for i: int in range(22):
				_bar(root, Vector3(-1.31 + float(i) * 0.125, 0.078, side * 1.50), Vector3(-1.31 + float(i) * 0.125, 0.073, side * 1.60), 0.014, fringe)

static func _lamp(root: Node3D, variant: String, tint: Color) -> void:
	var metal: Material = _mat(BRASS, 0, 0.30, 0.78)
	var dark_metal: Material = _mat(DARK, 0, 0.35, 0.65)
	_cylinder(root, Vector3(0, 0.10, 0), 0.30, 0.11, metal if variant != "basic" else dark_metal)
	_ring(root, Vector3(0, 0.13, 0), 0.27, 0.025, metal if variant != "basic" else dark_metal)
	if variant == "basic":
		_cylinder(root, Vector3(0, 1.02, 0), 0.035, 1.84, _mat(tint.darkened(0.20), 1))
		_cylinder(root, Vector3(0, 2.02, 0), 0.37, 0.48, _mat(tint.lightened(0.20), 2, 0.95), 0.24)
		_ring(root, Vector3(0, 1.78, 0), 0.365, 0.02, _mat(CREAM))
		_ring(root, Vector3(0, 2.26, 0), 0.238, 0.016, _mat(CREAM))
	elif variant == "comfort":
		# A sculpted swan-neck arc fits inside the same 0.8 m footprint.
		var previous: Vector3 = Vector3(-0.18, 0.14, 0)
		for i: int in range(1, 13):
			var f: float = float(i) / 12.0
			var current: Vector3 = Vector3(-0.18 + 0.36 * pow(f, 3.0), 0.14 + 2.18 * sin(f * PI * 0.53), 0)
			_bar(root, previous, current, 0.028, metal)
			previous = current
		var shade: MeshInstance3D = _sphere(root, Vector3(0.15, 2.14, 0), Vector3(0.23, 0.13, 0.23), _mat(tint, 0, 0.30, 0.20))
		shade.rotation.z = -0.18
		_ring(root, Vector3(0.15, 2.08, 0), 0.21, 0.016, metal)
	else:
		_cylinder(root, Vector3(0, 1.05, 0), 0.035, 1.90, dark_metal)
		for y: float in [0.38, 1.66, 1.82]:
			_sphere(root, Vector3(0, y, 0), Vector3(0.08, 0.095, 0.08), metal)
		# Colored glass wedge panels and dark seams form a Tiffany-style shade.
		for i: int in range(12):
			var a: float = float(i) * TAU / 12.0
			var b: float = float(i + 1) * TAU / 12.0
			var surface: SurfaceTool = SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var points: Array[Vector3] = [Vector3(cos(a)*0.35,1.96,sin(a)*0.35),Vector3(cos(b)*0.35,1.96,sin(b)*0.35),Vector3(cos(b)*0.14,2.28,sin(b)*0.14),Vector3(cos(a)*0.14,2.28,sin(a)*0.14)]
			for index: int in [0, 2, 1, 0, 3, 2]:
				surface.set_uv(Vector2.ZERO)
				surface.add_vertex(points[index])
			surface.generate_normals()
			var color: Color = [tint, Color("afae76"), Color("69978c")][i % 3]
			_mesh(root, surface.commit(), Vector3.ZERO, _glow(color))
			_bar(root, points[0], points[3], 0.013, dark_metal)
		_ring(root, Vector3(0, 1.96, 0), 0.35, 0.018, dark_metal)
		_ring(root, Vector3(0, 2.28, 0), 0.14, 0.014, dark_metal)
	_sphere(root, Vector3(0.10 if variant == "comfort" else 0.0, 1.95, 0), Vector3.ONE * 0.08, _glow(Color("e8c88a")))

static func _shelf(root: Node3D, variant: String, tint: Color) -> void:
	var wood: Material = _mat(tint, 1, 0.64)
	var dark: Material = _mat(tint.darkened(0.20), 1, 0.62)
	var brass: Material = _mat(BRASS, 0, 0.35, 0.65)
	var height: float = 1.85 if variant == "basic" else (2.12 if variant == "comfort" else 2.34)
	if variant == "premium":
		wood = _mat(Color("705440").lerp(tint, 0.25), 1, 0.47)
		dark = _mat(Color("4b4034"), 1, 0.54)
	for x: float in [-0.82, 0.82]:
		_box(root, Vector3(x, height * 0.5 + 0.08, 0), Vector3(0.12, height, 0.74), wood, 0.035)
	if variant != "basic":
		_box(root, Vector3(0, height * 0.5 + 0.08, -0.34), Vector3(1.60, height, 0.07), dark)
	for i: int in range(3 if variant == "basic" else 4):
		var y: float = 0.18 + float(i) * (height - 0.12) / (2.0 if variant == "basic" else 3.0)
		_box(root, Vector3(0, y, 0), Vector3(1.78, 0.10, 0.78), wood, 0.025)
	if variant == "comfort":
		var glass: Material = _glass(Color("a3bcb2"))
		for side: float in [-1.0, 1.0]:
			_box(root, Vector3(side * 0.41, 1.20, 0.365), Vector3(0.70, 1.65, 0.02), glass, 0.002)
			for x: float in [-0.36, 0.36]:
				_box(root, Vector3(side * 0.41 + x, 1.20, 0.38), Vector3(0.045, 1.74, 0.04), wood)
			for y: float in [0.33, 2.07]:
				_box(root, Vector3(side * 0.41, y, 0.38), Vector3(0.74, 0.045, 0.04), wood)
			_sphere(root, Vector3(side * 0.09, 1.18, 0.37), Vector3(0.035, 0.035, 0.025), brass)
	elif variant == "premium":
		_box(root, Vector3(0, height + 0.17, 0), Vector3(1.8, 0.13, 0.8), wood, 0.04)
		for side: float in [-1.0, 1.0]:
			_box(root, Vector3(side * 0.40, 0.45, 0.35), Vector3(0.72, 0.48, 0.07), wood, 0.03)
			_box(root, Vector3(side * 0.40, 0.45, 0.39), Vector3(0.54, 0.30, 0.012), dark)
			_sphere(root, Vector3(side * 0.13, 0.47, 0.37), Vector3(0.035, 0.035, 0.025), brass)
		_box(root, Vector3(0, height - 0.08, -0.16), Vector3(1.45, 0.025, 0.10), _glow(Color("d9bd83")))
		for x: float in [-0.77, 0.77]:
			_cylinder(root, Vector3(x, 0.08, 0), 0.055, 0.15, brass)
	# Curated books, ceramics and a shell give each tier a distinct display.
	for i: int in range(4):
		_box(root, Vector3(-0.55 + float(i) * 0.16, 0.48, -0.02), Vector3(0.12, 0.48 + float(i % 2) * 0.08, 0.37), _mat([Color("879c88"), Color("c1a377"), Color("aa7866")][i % 3]), 0.01)
	var vase_y: float = 1.20 if variant == "basic" else 1.18
	_cylinder(root, Vector3(0.38, vase_y, 0), 0.14, 0.38, _mat(CREAM, 0, 0.30), 0.09)
	_sphere(root, Vector3(-0.36, vase_y, 0), Vector3(0.19, 0.15, 0.14), _mat(tint.lightened(0.28), 0, 0.30))
	if variant != "basic":
		_cylinder(root, Vector3(0.40, 1.79, 0), 0.18, 0.08, _mat(CREAM, 0, 0.34))
		var shell: MeshInstance3D = _sphere(root, Vector3(-0.30, 1.85, 0), Vector3(0.24, 0.20, 0.065), _mat(Color("c5aa8d"), 0, 0.56))
		shell.rotation.x = -0.25




