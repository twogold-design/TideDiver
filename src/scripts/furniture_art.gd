class_name FurnitureArt
extends RefCounted
## Shared furniture models for the restaurant and live shop previews.
## build() returns an origin-centred model. The caller applies layout transforms.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _surface_shader: Shader
static var _rug_shader: Shader
static var _font: Font

const CREAM: Color = Color("8fa7af") # Muted mist blue, also used for tableware and canvas.
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
	} else if (surface_kind == 4) {
		float stripe = smoothstep(-0.08, 0.08, sin(p.x * 28.0));
		float fade = 1.0 / (1.0 + fwidth(p.x) * 45.0);
		color = mix(vec3(0.32, 0.43, 0.48), base_color.rgb, mix(0.5, stripe, fade));
		float weave = sin(p.x * 145.0) * sin((p.z + p.y) * 145.0) / (1.0 + length(fwidth(p)) * 120.0);
		color *= 0.97 + weave * 0.025;
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
	var palette: Array[Color] = [Color("b19570"), Color("69929a"), Color("bc8974")]
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
		"bench":
			_bench(root, variant, tint)
			# Face the same +Z direction as the shop display and other fronted items.
			for part: Node3D in root.get_children():
				part.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * part.transform
		"parasol": _parasol(root, variant, tint)
		"coastal": _coastal(root, variant, tint)
	_merge_geometry(root)
	if kind == "table" and seat >= 0:
		_table_number(root, seat)
	return root

# Harbor collection: fixed footprints and seat anchors keep existing layouts valid.
static func _text(parent: Node3D, message: String, pos: Vector3, scale: float = 0.004, color: Color = CREAM) -> Label3D:
	if _font == null:
		_font = preload("res://assets/fonts/ui_font.tres")
	var label := Label3D.new()
	label.font = _font
	label.text = message
	label.font_size = 32
	label.pixel_size = scale
	label.position = pos
	label.modulate = color
	label.outline_size = 0
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)
	return label

static func _table_number(parent: Node3D, seat: int) -> void:
	_box(parent, Vector3(0.40, 1.46, 0.52), Vector3(0.25, 0.25, 0.035), _mat(CREAM))
	_text(parent, str(seat + 1), Vector3(0.40, 1.46, 0.55), 0.005, DARK)

static func _rope(parent: Node3D, pos: Vector3, radius: float, loops: int = 3) -> void:
	for i: int in range(loops):
		_ring(parent, pos + Vector3.UP * i * 0.032, radius, 0.018, _mat(Color("aa9672"), 2))

static func _rattan(parent: Node3D, center: Vector3, size: Vector2) -> void:
	var cane := _mat(Color("aa8a5b"), 1)
	# Open woven panel, with thicker framing; no opaque solid behind it.
	for i: int in range(13):
		var x: float = -size.x * 0.5 + size.x * i / 12.0
		_bar(parent, center + Vector3(x, -size.y * 0.5, 0), center + Vector3(x, size.y * 0.5, 0), 0.011, cane)
	for i: int in range(10):
		var y: float = -size.y * 0.5 + size.y * i / 9.0
		_bar(parent, center + Vector3(-size.x * 0.5, y, -0.006), center + Vector3(size.x * 0.5, y, -0.006), 0.012, cane)
	for side: float in [-1, 1]:
		_bar(parent, center + Vector3(side * size.x * 0.5, -size.y * 0.5, 0), center + Vector3(side * size.x * 0.5, size.y * 0.5, 0), 0.028, cane)
		_bar(parent, center + Vector3(-size.x * 0.5, side * size.y * 0.5, 0), center + Vector3(size.x * 0.5, side * size.y * 0.5, 0), 0.028, cane)

static func _plate(parent: Node3D, pos: Vector3, radius: float = 0.17) -> void:
	_cylinder(parent, pos, radius, 0.022, _mat(CREAM, 0, 0.30))
	_ring(parent, pos + Vector3.UP * 0.012, radius * 0.84, 0.012, _mat(Color("567b88")))

static func _bottle(parent: Node3D, pos: Vector3, color: Color) -> void:
	_cylinder(parent, pos + Vector3.UP * 0.10, 0.055, 0.20, _mat(color, 0, 0.25), 0.045)
	_cylinder(parent, pos + Vector3.UP * 0.23, 0.023, 0.08, _mat(color, 0, 0.25))
	_cylinder(parent, pos + Vector3.UP * 0.27, 0.025, 0.035, _mat(DARK))
	_box(parent, pos + Vector3(0, 0.11, 0.052), Vector3(0.06, 0.07, 0.006), _mat(CREAM), 0.002)

static func _table(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint, 1)
	var pale := _mat(Color("7e99a3").lerp(tint, 0.05), 1, 0.94)
	var frame: Material = pale if variant == "comfort" else _mat(tint.darkened(0.22), 1)
	var blue := _mat(Color("50768b").lerp(tint, 0.18), 4)
	if variant == "comfort":
		_cylinder(root, Vector3(0, 1.27, 0), 1.03, 0.13, pale)
		_ring(root, Vector3(0, 1.28, 0), 1.005, 0.025, wood)
		# Fine plank joints and inset edging remain visible under the beach sun.
		_ring(root, Vector3(0, 1.338, 0), 0.94, 0.009, _mat(Color("657e86"), 1))
		for x: float in [-0.61, -0.30, 0, 0.30, 0.61]:
			var length: float = sqrt(0.93 * 0.93 - x * x)
			_bar(root, Vector3(x, 1.337, -length), Vector3(x, 1.337, length), 0.004, _mat(Color("667e87")))
		_cylinder(root, Vector3(0, 0.69, 0), 0.10, 1.1, frame)
		for i: int in range(4):
			var a: float = i * PI / 2
			_bar(root, Vector3(0, 0.4, 0), Vector3(cos(a) * 0.63, 0.08, sin(a) * 0.63), 0.065, frame)
	else:
		for i: int in range(6):
			_box(root, Vector3(-0.875 + i * 0.35, 1.27, 0), Vector3(0.335, 0.13, 1.70), _mat(tint.lightened((i % 3) * 0.025), 1), 0.018)
		for x: float in [-0.80, 0.80]:
			_box(root, Vector3(x, 1.12, 0), Vector3(0.12, 0.17, 1.43), frame)
			for z: float in [-0.62, 0.62]:
				_bar(root, Vector3(x, 1.17, z), Vector3(x * 1.06, 0.08, z * 1.05), 0.06, frame)
				_cylinder(root, Vector3(x, 1.34, z), 0.016, 0.008, _mat(DARK))
		if variant == "premium":
			_box(root, Vector3(0, 1.342, 0), Vector3(0.43, 0.015, 1.62), blue, 0.005)
	for side: float in [-1, 1]:
		var z: float = side * 1.40
		_box(root, Vector3(0, 0.70, z), Vector3(0.85, 0.10, 0.70), frame)
		if variant == "basic":
			for x: float in [-0.34, 0.34]:
				_bar(root, Vector3(x, 0.74, z - 0.27), Vector3(x, 0.06, z + 0.31), 0.035, frame)
				_bar(root, Vector3(x, 0.74, z + 0.27), Vector3(x, 0.06, z - 0.31), 0.035, frame)
				_bar(root, Vector3(x, 0.68, z + side * 0.30), Vector3(x, 1.43, z + side * 0.34), 0.035, frame)
			for y: float in [1.18, 1.38]:
				_box(root, Vector3(0, y, z + side * 0.34), Vector3(0.83, 0.14, 0.08), wood)
		else:
			for x: float in [-0.33, 0.33]:
				for dz: float in [-0.25, 0.25]:
					_bar(root, Vector3(x, 0.72, z + dz), Vector3(x * 1.08, 0.07, z + dz * 1.12), 0.04, frame)
			_box(root, Vector3(0, 0.78, z), Vector3(0.82, 0.12, 0.67), _mat(CREAM, 2) if variant == "comfort" else blue, 0.045)
			if variant == "comfort":
				_rattan(root, Vector3(0, 1.22, z + side * 0.34), Vector2(0.77, 0.65))
			else:
				_box(root, Vector3(0, 1.22, z + side * 0.34), Vector3(0.83, 0.74, 0.12), frame, 0.045)
				_box(root, Vector3(0, 1.24, z + side * 0.265), Vector3(0.77, 0.62, 0.09), blue, 0.045)
		_plate(root, Vector3(0, 1.35, side * 0.55), 0.19)
		_box(root, Vector3(0.29, 1.35, side * 0.56), Vector3(0.13, 0.018, 0.25), _mat(CREAM, 2), 0.005)
	_cylinder(root, Vector3(-0.43, 1.43, 0.38), 0.07, 0.17, _mat(Color("87a8a8"), 0, 0.27))
	_bottle(root, Vector3(-0.40, 1.35, -0.15), Color("7d8d59"))

static func _plant(root: Node3D, variant: String, tint: Color) -> void:
	var clay := _mat(Color("b38c70").lerp(tint, 0.35), 0, 0.85)
	var soil := _mat(Color("514737"))
	var green := _mat(Color("63885a"))
	if variant == "comfort":
		for side: float in [-1, 1]:
			for y: float in [0.14, 0.30, 0.46]:
				_box(root, Vector3(side * 0.32, y, 0), Vector3(0.06, 0.13, 0.66), _mat(tint, 1))
				_box(root, Vector3(0, y, side * 0.32), Vector3(0.66, 0.13, 0.06), _mat(tint, 1))
		_box(root, Vector3(0, 0.46, 0), Vector3(0.58, 0.06, 0.58), soil)
	else:
		var height: float = 0.46 if variant == "basic" else 0.66
		_cylinder(root, Vector3(0, height * 0.5, 0), 0.23, height, clay, 0.32)
		_ring(root, Vector3(0, height, 0), 0.30, 0.025, clay)
		_cylinder(root, Vector3(0, height - 0.02, 0), 0.275, 0.025, soil)
		for i: int in range(8):
			var a: float = i * 2.399
			_sphere(root, Vector3(cos(a) * 0.20, height, sin(a) * 0.20), Vector3(0.055, 0.025, 0.04), _mat(CREAM.darkened(i % 3 * 0.08)))
	if variant == "premium":
		_bar(root, Vector3(0, 0.60, 0), Vector3(0.06, 1.55, 0), 0.055, _mat(tint.darkened(0.22), 1))
		for y: float in [0.78, 0.92, 1.06, 1.20, 1.34]:
			_ring(root, Vector3(0.06 * (y - 0.6), y, 0), 0.052, 0.008, _mat(Color("b9a180")))
		for i: int in range(8):
			var a: float = i * TAU / 8
			var start := Vector3(0.03, 1.54, 0)
			var end := Vector3(cos(a) * 0.32, 1.42 + (i % 2) * 0.22, sin(a) * 0.32)
			_bar(root, start, end, 0.012, green)
			for j: int in range(1, 6):
				var p: Vector3 = start.lerp(end, j / 6.0)
				for side: float in [-1, 1]:
					var leaf := _sphere(root, p + Vector3(cos(a + side * 1.2), -0.02, sin(a + side * 1.2)) * 0.045, Vector3(0.025, 0.012, 0.095), green)
					leaf.rotation = Vector3(0.32, -a + side * 0.65, 0)
	else:
		for i: int in range(9 if variant == "comfort" else 6):
			var a: float = i * 2.399
			var p := Vector3(cos(a) * 0.18, 0.77 + (i % 3) * 0.12, sin(a) * 0.18)
			_bar(root, Vector3(p.x * 0.6, 0.45, p.z * 0.6), p, 0.011, green)
			for side: float in [-1, 1]:
				var leaf := _sphere(root, p + Vector3(side * 0.045, -0.07, 0), Vector3(0.075, 0.025, 0.13), green)
				leaf.rotation = Vector3(-0.35, a + side, 0.2)
			if variant == "comfort":
				for petal: int in range(5):
					var angle: float = petal * TAU / 5
					_sphere(root, p + Vector3(cos(angle) * 0.028, 0, sin(angle) * 0.028), Vector3(0.025, 0.015, 0.025), _mat(CREAM if i % 2 else Color("d19d83")))

static func _woven_rug(tint: Color) -> Material:
	var key: String = "harbor-woven:" + tint.to_html()
	if _materials.has(key):
		return _materials[key]
	if _rug_shader == null:
		_rug_shader = Shader.new()
		_rug_shader.code = """
shader_type spatial;
uniform vec4 sea : source_color;
varying vec3 p;
void vertex() { p = VERTEX; }
void fragment() {
	vec2 q = p.xz;
	vec2 a = abs(q / vec2(1.37, 1.55));
	float edge = max(a.x, a.y);
	float aa = max(fwidth(edge), 0.003);
	vec3 sand = vec3(0.38, 0.30, 0.20);
	float twill = sin((q.x + abs(fract(q.y * 8.0) - 0.5) * 0.10) * 150.0);
	float weave = twill * sin(q.y * 180.0) / (1.0 + length(fwidth(q)) * 180.0);
	vec3 color = sand * (1.0 + 0.13 * weave + 0.025 * sin(q.y * 23.0));
	float border = smoothstep(0.73-aa, 0.73+aa, edge) * (1.0-smoothstep(0.92-aa, 0.92+aa, edge));
	color = mix(color, sea.rgb * (0.84 + weave * 0.10), border);
	float braid = abs(sin((a.x > a.y ? q.y : q.x) * 46.0 + sin(edge * 105.0)));
	float piping = (1.0-smoothstep(0.012, 0.012+aa, abs(edge-0.77))) + (1.0-smoothstep(0.012, 0.012+aa, abs(edge-0.88)));
	color = mix(color, vec3(0.48,0.39,0.27), clamp(piping,0.0,1.0) * braid * 0.75);
	// Subtle woven waves leave the centre calm, with a crafted coastal motif.
	float wave = abs(q.y - 0.08 * sin(q.x * 5.0));
	float motif = (1.0-smoothstep(0.012,0.023+fwidth(wave),abs(wave-0.14))) * (1.0-smoothstep(0.78,0.86,abs(q.x)));
	color = mix(color, sea.rgb, motif * 0.62);
	ALBEDO = color;
	ROUGHNESS = 0.98;
	SPECULAR = 0.12;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _rug_shader
	mat.set_shader_parameter("sea", Color("496777").lerp(tint, 0.08))
	_materials[key] = mat
	return mat

static func _rug(root: Node3D, variant: String, tint: Color) -> void:
	var sand := _mat(Color("b39c74").lerp(tint, 0.15), 2)
	var blue := _mat(Color("547c8d").lerp(tint, 0.12), 2)
	var body: Material = _mat(Color("52798b").lerp(tint, 0.18), 4) if variant == "comfort" else sand
	if variant == "premium":
		body = _woven_rug(tint)
	_box(root, Vector3(0, 0.08, 0), Vector3(2.74, 0.035, 3.10), body, 0.015)
	var edge: Material = _mat(Color("76664e"), 2) if variant == "basic" else blue
	for side: float in [-1, 1]:
		_box(root, Vector3(side * 1.34, 0.095, 0), Vector3(0.10, 0.025, 3.10), edge, 0.008)
		_box(root, Vector3(0, 0.095, side * 1.50), Vector3(2.70, 0.025, 0.10), edge, 0.008)
	if variant == "basic":
		var label := _text(root, "WELCOME", Vector3(0, 0.105, 0), 0.009, Color("5e513d"))
		label.rotation.x = -PI / 2
		for i: int in range(22):
			_box(root, Vector3(-1.22 + i * 0.116, 0.101, 0), Vector3(0.018, 0.008, 2.78), _mat(Color("a28b63"), 2), 0.002)
	elif variant == "premium":
		var stitch := _mat(Color("ad9978"), 2, 0.98)
		# Raised binding and individual stitches sit above the woven surface.
		for side: float in [-1, 1]:
			for i: int in range(42):
				var z: float = -1.44 + i * 2.88 / 41.0
				_bar(root, Vector3(side * 1.30, 0.113, z - 0.012), Vector3(side * 1.37, 0.113, z + 0.012), 0.0045, stitch)
			for i: int in range(36):
				var x: float = -1.26 + i * 2.52 / 35.0
				_bar(root, Vector3(x - 0.012, 0.113, side * 1.46), Vector3(x + 0.012, 0.113, side * 1.53), 0.0045, stitch)
		for side: float in [-1, 1]:
			for i: int in range(22):
				var x: float = -1.25 + i * 0.119
				_sphere(root, Vector3(x, 0.086, side * 1.55), Vector3(0.022, 0.012, 0.018), stitch)
				for strand: float in [-0.012, 0, 0.012]:
					_bar(root, Vector3(x, 0.084, side * 1.54), Vector3(x + strand, 0.075, side * 1.59), 0.005, stitch)

static func _lantern(parent: Node3D, pos: Vector3, scale: float, tint: Color) -> void:
	# Explicit points avoid temporary nodes and preserve the static batching pass.
	var metal := _mat(DARK, 0, 0.48, 0.4)
	_cylinder(parent, pos, 0.20 * scale, 0.08 * scale, metal)
	_cylinder(parent, pos + Vector3.UP * 0.42 * scale, 0.22 * scale, 0.13 * scale, _mat(tint, 0, 0.5), 0.09 * scale)
	_cylinder(parent, pos + Vector3.UP * 0.20 * scale, 0.12 * scale, 0.30 * scale, _glass(Color("e5d5a9")))
	_sphere(parent, pos + Vector3.UP * 0.19 * scale, Vector3(0.067, 0.13, 0.067) * scale, _glow(Color("e9bb71")))
	for i: int in range(6):
		var a: float = i * TAU / 6
		var p := Vector3(cos(a) * 0.16, 0, sin(a) * 0.16) * scale
		_bar(parent, pos + p, pos + p + Vector3.UP * 0.40 * scale, 0.015 * scale, metal)
	var handle := _ring(parent, pos + Vector3.UP * 0.57 * scale, 0.12 * scale, 0.016 * scale, metal)
	handle.rotation.x = PI / 2

static func _lamp(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint, 1)
	if variant == "premium":
		_mast_lamp(root, tint)
		return
	if variant == "basic":
		_cylinder(root, Vector3(0, 0.11, 0), 0.28, 0.22, wood)
		_lantern(root, Vector3(0, 0.26, 0), 1.3, tint)
	else:
		_cylinder(root, Vector3(0, 0.09, 0), 0.33, 0.18, _mat(Color("89918a"), 0))
		_box(root, Vector3(0, 1.12, 0), Vector3(0.12, 2.15, 0.12), wood)
		_rope(root, Vector3(0, 0.22, 0), 0.085, 6)
		_box(root, Vector3(0, 2.04, 0), Vector3(0.67, 0.09, 0.10), wood)
		for side: float in [-1, 1]:
			if variant == "comfort" and side < 0:
				continue
			var x: float = side * 0.23
			_bar(root, Vector3(x, 2.04, 0), Vector3(x, 1.89, 0), 0.014, _mat(DARK, 0, 0.5, 0.4))
			_lantern(root, Vector3(x, 1.40, 0), 0.7, tint)
			_bar(root, Vector3(0, 1.65, 0), Vector3(side * 0.27, 2, 0), 0.022, wood)

static func _mast_lamp(root: Node3D, tint: Color) -> void:
	var timber := _mat(tint.darkened(0.17), 1, 0.88)
	var iron := _mat(Color("2f4851"), 0, 0.76, 0.28)
	var bronze := _mat(Color("8e7856"), 0, 0.72, 0.32)
	_cylinder(root, Vector3(0, 0.055, 0), 0.31, 0.11, iron)
	_cylinder(root, Vector3(0, 0.15, 0), 0.22, 0.10, bronze, 0.16)
	_cylinder(root, Vector3(0, 0.32, 0), 0.13, 0.30, iron, 0.09)
	_cylinder(root, Vector3(0, 1.30, 0), 0.080, 1.85, timber, 0.055)
	for y: float in [0.48, 0.61, 1.56, 1.80, 2.14]:
		_ring(root, Vector3(0, y, 0), 0.083 if y < 1 else 0.067, 0.014, bronze)
	_sphere(root, Vector3(0, 2.24, 0), Vector3(0.072, 0.095, 0.072), bronze)
	_cylinder(root, Vector3(0, 2.16, 0), 0.089, 0.05, iron)
	for i: int in range(6):
		var a: float = i * TAU / 6
		_cylinder(root, Vector3(cos(a) * 0.245, 0.118, sin(a) * 0.245), 0.017, 0.015, bronze)
	_rope(root, Vector3(0, 0.67, 0), 0.087, 5)
	var knot := _ring(root, Vector3(0.04, 0.73, 0.095), 0.035, 0.013, _mat(Color("948263"), 2))
	knot.rotation.x = PI / 2
	_bar(root, Vector3(0.03, 0.73, 0.10), Vector3(0.08, 0.55, 0.10), 0.012, _mat(Color("948263"), 2))
	for side: float in [-1, 1]:
		# Forged arch, hanging chain and a curved supporting brace.
		var previous := Vector3(0, 1.92, 0)
		for i: int in range(1, 13):
			var t: float = i / 12.0
			var point := Vector3(side * 0.23 * t, 1.92 + sin(t * PI * 0.75) * 0.24, 0)
			_bar(root, previous, point, 0.021, iron)
			previous = point
		for i: int in range(3):
			var link := _ring(root, Vector3(side * 0.23, 2.06 - i * 0.045, 0), 0.027, 0.007, bronze)
			link.rotation = Vector3(PI / 2, i % 2 * PI / 2, 0)
		previous = Vector3(0, 1.68, 0)
		for i: int in range(1, 9):
			var t: float = i / 8.0
			var point := Vector3(side * 0.17 * sin(t * PI / 2), 1.68 + t * 0.34, 0)
			_bar(root, previous, point, 0.012, bronze)
			previous = point
		var base := Vector3(side * 0.23, 1.38, 0)
		_cylinder(root, base, 0.135, 0.055, iron)
		_cylinder(root, base + Vector3.UP * 0.035, 0.113, 0.025, bronze)
		_cylinder(root, base + Vector3.UP * 0.24, 0.088, 0.36, _glass(Color("91aeb2")))
		_cylinder(root, base + Vector3.UP * 0.13, 0.045, 0.09, bronze)
		_sphere(root, base + Vector3.UP * 0.235, Vector3(0.032, 0.085, 0.032), _glow(Color("b58e57")))
		for y: float in [0.08, 0.38]:
			_ring(root, base + Vector3.UP * y, 0.106, 0.012, bronze)
		for i: int in range(8):
			var a: float = i * TAU / 8
			var offset := Vector3(cos(a) * 0.104, 0, sin(a) * 0.104)
			_bar(root, base + offset + Vector3.UP * 0.05, base + offset + Vector3.UP * 0.40, 0.008, iron)
			_sphere(root, base + offset + Vector3.UP * 0.075, Vector3.ONE * 0.012, bronze)
		_cylinder(root, base + Vector3.UP * 0.425, 0.14, 0.095, iron, 0.065)
		_ring(root, base + Vector3.UP * 0.38, 0.133, 0.010, bronze)
		_cylinder(root, base + Vector3.UP * 0.495, 0.051, 0.055, bronze)
		for i: int in range(8):
			var a: float = i * TAU / 8
			_box(root, base + Vector3(cos(a) * 0.047, 0.497, sin(a) * 0.047), Vector3(0.016, 0.029, 0.014), iron, 0.003)
		var handle := _ring(root, base + Vector3.UP * 0.565, 0.042, 0.009, iron)
		handle.rotation.x = PI / 2

static func _bench(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint, 1)
	var pale := _mat(Color("819ba4").lerp(tint, 0.08), 1, 0.90)
	var blue := _mat(Color("52798b").lerp(tint, 0.18), 4)
	if variant == "premium":
		for x: float in [-0.97, 0.97]:
			for z: float in [-0.10, 0.37]:
				_bar(root, Vector3(x, 0.07, z), Vector3(x, 0.62, z), 0.043, wood)
			_box(root, Vector3(x, 0.83, 0.13), Vector3(0.10, 0.10, 0.62), wood)
		_box(root, Vector3(0, 0.56, 0.16), Vector3(2.02, 0.12, 0.60), wood)
		_rattan(root, Vector3(0, 0.94, 0.42), Vector2(1.96, 0.70))
		for x: float in [-0.49, 0.49]:
			_box(root, Vector3(x, 0.67, 0.16), Vector3(0.93, 0.17, 0.52), _mat(CREAM, 2), 0.06)
			_box(root, Vector3(x, 0.95, 0.32), Vector3(0.79, 0.43, 0.12), blue, 0.05)
		_box(root, Vector3(0, 0.38, -0.34), Vector3(0.81, 0.07, 0.29), wood)
		for x: float in [-0.30, 0.30]:
			_box(root, Vector3(x, 0.20, -0.34), Vector3(0.055, 0.36, 0.20), wood)
		_cylinder(root, Vector3(0.15, 0.46, -0.34), 0.045, 0.10, _mat(CREAM, 0, 0.3))
		return
	for x: float in [-0.86, 0.86]:
		var leg := _box(root, Vector3(x, 0.29, 0), Vector3(0.18, 0.57, 0.65), wood if variant == "basic" else pale)
		leg.rotation.z = x * 0.09
	for z: float in [-0.27, 0, 0.27]:
		_box(root, Vector3(0, 0.61, z), Vector3(2.20, 0.11, 0.25), wood if variant == "basic" else pale)
	if variant == "basic":
		_bar(root, Vector3(-0.9, 0.23, 0), Vector3(0.9, 0.23, 0), 0.06, wood)
	else:
		for x: float in [-0.97, 0.97]:
			_bar(root, Vector3(x, 0.58, 0.36), Vector3(x, 1.25, 0.39), 0.045, pale)
		for y: float in [0.95, 1.17]:
			_box(root, Vector3(0, y, 0.39), Vector3(2.08, 0.15, 0.07), pale)
		_box(root, Vector3(0, 0.72, 0), Vector3(2.06, 0.13, 0.68), blue, 0.05)
		for x: float in [-0.78, 0.78]:
			_box(root, Vector3(x, 0.97, 0.23), Vector3(0.35, 0.36, 0.14), _mat(CREAM, 2), 0.06)

static func _quad(parent: Node3D, points: Array[Vector3], material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0, 1, 2, 0, 2, 3, 2, 1, 0, 3, 2, 0]:
		surface.add_vertex(points[index])
	surface.generate_normals()
	_mesh(parent, surface.commit(), Vector3.ZERO, material)

static func _parasol(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint, 1)
	var cloth := _mat(CREAM, 2)
	if variant == "premium":
		for x: float in [-1.20, 1.20]:
			for z: float in [-1.20, 1.20]:
				_box(root, Vector3(x, 1.25, z), Vector3(0.12, 2.5, 0.12), wood)
				_box(root, Vector3(x, 0.08, z), Vector3(0.22, 0.16, 0.22), _mat(DARK))
		for side: float in [-1, 1]:
			_box(root, Vector3(side * 1.20, 2.48, 0), Vector3(0.13, 0.16, 2.55), wood)
			_box(root, Vector3(0, 2.48, side * 1.20), Vector3(2.55, 0.16, 0.13), wood)
		for i: int in range(8):
			var x: float = -1.28 + i * 0.32
			_quad(root, [Vector3(x, 2.60, -1.28), Vector3(x + 0.32, 2.60, -1.28), Vector3(x + 0.32, 2.55, 1.28), Vector3(x, 2.55, 1.28)], cloth if i % 2 else _mat(Color("8eaaa7"), 2))
		# Partly lowered back blind and its rolled top; all stay inside the footprint.
		_box(root, Vector3(0, 2.22, -1.23), Vector3(2.20, 0.44, 0.025), cloth, 0.008)
		var roll := _cylinder(root, Vector3(0, 2.47, -1.23), 0.065, 2.24, cloth)
		roll.rotation.z = PI / 2
		for i: int in range(7):
			var x: float = -1.05 + i * 0.35
			var y: float = 2.33 - 0.13 * (1.0 - absf(x) / 1.05)
			if i > 0:
				var px: float = x - 0.35
				_bar(root, Vector3(px, 2.33 - 0.13 * (1.0 - absf(px) / 1.05), 1.20), Vector3(x, y, 1.20), 0.012, _mat(DARK))
			_sphere(root, Vector3(x, y - 0.055, 1.20), Vector3(0.043, 0.06, 0.043), _glow(Color("e8c282")))
		return
	_cylinder(root, Vector3(0, 0.09, 0), 0.34, 0.18, _mat(Color("89918a")))
	_cylinder(root, Vector3(0, 1.43, 0), 0.04, 2.78, wood)
	_rope(root, Vector3(0, 0.22, 0), 0.054, 4)
	for i: int in range(12):
		var a: float = i * TAU / 12
		var b: float = (i + 1) * TAU / 12
		var edge_a := Vector3(cos(a) * 1.31, 2.25, sin(a) * 1.31)
		var edge_b := Vector3(cos(b) * 1.31, 2.25, sin(b) * 1.31)
		var material: Material = cloth if variant == "basic" or i % 2 else _mat(Color("52798b").lerp(tint, 0.15), 2)
		_quad(root, [Vector3(0, 2.79, 0), edge_a, edge_b, Vector3(0, 2.79, 0)], material)
		_quad(root, [edge_a, edge_a - Vector3.UP * 0.13, edge_b - Vector3.UP * 0.13, edge_b], material)
		_bar(root, Vector3(0, 2.76, 0), edge_a - Vector3.UP * 0.02, 0.012, wood)
	_sphere(root, Vector3(0, 2.83, 0), Vector3(0.06, 0.08, 0.06), wood)

static func _fish_on_ice(parent: Node3D, pos: Vector3, scale: float = 1.0, angle: float = 0.0) -> void:
	var fish := Node3D.new()
	fish.position = pos
	fish.rotation.y = angle
	parent.add_child(fish)
	var silver := _mat(Color("9cafac"), 0, 0.38, 0.12)
	_sphere(fish, Vector3.ZERO, Vector3(0.25, 0.07, 0.10) * scale, silver)
	_sphere(fish, Vector3(-0.01, 0.04, 0), Vector3(0.20, 0.025, 0.055) * scale, _mat(Color("537681")))
	_quad(fish, [Vector3(-0.20, 0.02, 0) * scale, Vector3(-0.33, 0.025, -0.11) * scale, Vector3(-0.29, 0.025, 0) * scale, Vector3(-0.33, 0.025, 0.11) * scale], silver)
	for side: float in [-1, 1]:
		_sphere(fish, Vector3(0.17, 0.045, side * 0.065) * scale, Vector3.ONE * 0.014 * scale, _mat(DARK))
	# Bake local fish transform into its meshes so the furniture can batch them too.
	for node: Node in fish.get_children():
		var part := node as MeshInstance3D
		var transform: Transform3D = fish.transform * part.transform
		fish.remove_child(part)
		parent.add_child(part)
		part.transform = transform
	parent.remove_child(fish)
	fish.free()

static func _ice(parent: Node3D, pos: Vector3, size: Vector2) -> void:
	var tray := _mat(Color("4f686b"), 0, 0.69, 0.12)
	_box(parent, pos - Vector3.UP * 0.015, Vector3(size.x, 0.07, size.y), tray, 0.02)
	_box(parent, pos + Vector3.UP * 0.018, Vector3(size.x - 0.055, 0.028, size.y - 0.055), _mat(Color("688a8c"), 0, 0.73), 0.012)
	for i: int in range(34):
		var p := pos + Vector3(sin(i * 7.3) * size.x * 0.40, 0.042 + (i % 3) * 0.003, cos(i * 4.7) * size.y * 0.37)
		var color: Color = [Color("7d999b"), Color("8ba7a6"), Color("729396")][i % 3]
		var chip := _box(parent, p, Vector3(0.055 + (i % 3) * 0.01, 0.028, 0.048), _mat(color, 0, 0.64), 0.008)
		chip.rotation = Vector3(0.10 * sin(i), i * 1.7, 0.12 * cos(i))

static func _shelf(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint, 1)
	var pale := _mat(Color("819ba4").lerp(tint, 0.10), 1, 0.90)
	if variant == "premium":
		pale = _mat(Color("748d98").lerp(tint, 0.06), 1, 0.94)
	if variant == "basic":
		for x: float in [-0.82, 0.82]:
			for z: float in [-0.32, 0.32]:
				_box(root, Vector3(x, 0.95, z), Vector3(0.07, 1.88, 0.07), wood)
		for y: float in [0.16, 0.88, 1.60]:
			_box(root, Vector3(0, y, 0), Vector3(1.76, 0.08, 0.76), wood)
			for i: int in range(4):
				_plate(root, Vector3(-0.39, y + 0.055 + i * 0.025, 0.03), 0.20)
			for x: float in [0.20, 0.44, 0.66]:
				_cylinder(root, Vector3(x, y + 0.13, 0.04), 0.075, 0.18, _mat(CREAM, 0, 0.3))
				var handle := _ring(root, Vector3(x + 0.08, y + 0.13, 0.04), 0.041, 0.012, _mat(CREAM, 0, 0.3))
				handle.rotation.x = PI / 2
		_bar(root, Vector3(-0.78, 0.2, -0.34), Vector3(0.78, 1.82, -0.34), 0.026, wood)
		return
	_box(root, Vector3(0, 0.57, 0), Vector3(1.72, 1.04, 0.70), pale)
	for x: float in [-0.72, 0.72]:
		for z: float in [-0.26, 0.26]:
			_box(root, Vector3(x, 0.10, z), Vector3(0.10, 0.20, 0.10), wood)
	_box(root, Vector3(0, 1.12, 0), Vector3(1.78, 0.10, 0.78), wood)
	for side: float in [-1, 1]:
		_box(root, Vector3(side * 0.41, 0.58, 0.359), Vector3(0.74, 0.82, 0.035), _mat(DARK))
		for i: int in range(8):
			var slat := _box(root, Vector3(side * 0.41, 0.24 + i * 0.095, 0.372), Vector3(0.71, 0.075, 0.035), pale, 0.006)
			slat.rotation.x = -0.20
		_sphere(root, Vector3(side * 0.09, 0.60, 0.385), Vector3(0.02, 0.025, 0.01), _mat(DARK))
	if variant == "comfort":
		for i: int in range(4):
			_bottle(root, Vector3(-0.65 + i * 0.17, 1.18, -0.08), Color("788d61") if i % 2 else Color("b48159"))
		for i: int in range(4):
			_plate(root, Vector3(0.44, 1.18 + i * 0.026, 0), 0.21)
		_box(root, Vector3(0.18, 1.18, 0.15), Vector3(0.14, 0.025, 0.30), _mat(CREAM, 2))
	else:
		_ice(root, Vector3(0, 1.21, 0), Vector2(1.61, 0.61))
		for i: int in range(3):
			_fish_on_ice(root, Vector3(-0.50 + i * 0.49, 1.29, 0), 0.74, -0.5)
		for x: float in [-0.61, 0.58]:
			_cylinder(root, Vector3(x, 1.30, 0.20), 0.06, 0.015, _mat(Color("d7bd63")))
		for x: float in [-0.82, 0.82]:
			_box(root, Vector3(x, 1.44, 0), Vector3(0.025, 0.49, 0.70), _glass(Color("a1c3c0")), 0.004)
			_bar(root, Vector3(x, 1.20, -0.34), Vector3(x, 1.67, -0.34), 0.015, _mat(DARK))
		_box(root, Vector3(0, 1.68, 0), Vector3(1.69, 0.02, 0.72), _glass(Color("a1c3c0")), 0.004)
		_box(root, Vector3(0, 1.44, -0.35), Vector3(1.66, 0.48, 0.02), _glass(Color("a1c3c0")), 0.004)
		_box(root, Vector3(0, 1.85, -0.25), Vector3(0.83, 0.30, 0.045), wood)
		_box(root, Vector3(0, 1.85, -0.219), Vector3(0.75, 0.23, 0.015), _mat(DARK))
		_text(root, "今日渔获  42G", Vector3(0, 1.85, -0.206), 0.0026)

static func _coastal(root: Node3D, variant: String, tint: Color) -> void:
	var wood := _mat(tint, 1)
	if variant == "basic":
		for x: float in [-0.43, 0.43]:
			_bar(root, Vector3(x, 0.06, -0.35), Vector3(x, 1.42, 0), 0.035, wood)
			_bar(root, Vector3(x, 0.06, 0.35), Vector3(x, 1.42, 0), 0.035, wood)
		_box(root, Vector3(0, 0.92, 0.09), Vector3(0.98, 1.03, 0.07), wood)
		_box(root, Vector3(0, 0.92, 0.134), Vector3(0.85, 0.89, 0.025), _mat(Color("294743")))
		_text(root, "今日鲜鱼\n———\n海盐鲜鱼\n香煎渔获", Vector3(0, 1.02, 0.154), 0.0037)
		# Chalk fish silhouette under the menu.
		_sphere(root, Vector3(0, 0.63, 0.155), Vector3(0.17, 0.055, 0.004), _mat(CREAM))
		_quad(root, [Vector3(-0.14, 0.63, 0.16), Vector3(-0.25, 0.70, 0.16), Vector3(-0.23, 0.63, 0.16), Vector3(-0.25, 0.56, 0.16)], _mat(CREAM))
		_box(root, Vector3(0, 0.42, 0.19), Vector3(0.95, 0.05, 0.17), wood)
	elif variant == "comfort":
		_box(root, Vector3(-0.10, 0.08, 0), Vector3(0.85, 0.12, 0.85), wood)
		for side: float in [-1, 1]:
			for y: float in [0.18, 0.34, 0.50]:
				_box(root, Vector3(-0.10 + side * 0.41, y, 0), Vector3(0.07, 0.13, 0.86), wood)
				_box(root, Vector3(-0.10, y, side * 0.41), Vector3(0.86, 0.13, 0.07), wood)
		_ice(root, Vector3(-0.10, 0.48, 0), Vector2(0.68, 0.67))
		_fish_on_ice(root, Vector3(-0.17, 0.57, -0.07), 0.85, 0.4)
		for i: int in range(2):
			_sphere(root, Vector3(0.31, 0.65 + i * 0.19, 0.15), Vector3(0.12, 0.16, 0.12), _mat(Color("b87958") if i == 0 else Color("689298")))
		_rope(root, Vector3(0.31, 0.04, -0.34), 0.18, 4)
	else:
		# A compact dinghy display: tapered bow, plank hull, gunwale and trestles.
		for z: float in [-0.30, 0.30]:
			_box(root, Vector3(0, 0.30, z), Vector3(0.68, 0.10, 0.12), wood)
			for x: float in [-0.25, 0.25]:
				_box(root, Vector3(x, 0.17, z), Vector3(0.085, 0.34, 0.12), wood)
		var sections: Array[Vector2] = [Vector2(-0.54, 0.04), Vector2(-0.32, 0.38), Vector2(0.27, 0.46), Vector2(0.51, 0.31)]
		for side: float in [-1, 1]:
			for i: int in range(sections.size() - 1):
				var a: Vector2 = sections[i]
				var b: Vector2 = sections[i + 1]
				for plank: int in range(3):
					var f: float = plank / 3.0
					var g: float = (plank + 1) / 3.0
					_quad(root, [Vector3(side * a.y * (0.65 + f * 0.35), 0.36 + f * 0.30, a.x), Vector3(side * b.y * (0.65 + f * 0.35), 0.36 + f * 0.30, b.x), Vector3(side * b.y * (0.65 + g * 0.35), 0.36 + g * 0.30, b.x), Vector3(side * a.y * (0.65 + g * 0.35), 0.36 + g * 0.30, a.x)], _mat(tint.lightened(plank * 0.06), 1))
				_bar(root, Vector3(side * a.y, 0.67, a.x), Vector3(side * b.y, 0.67, b.x), 0.026, _mat(Color("9c937b"), 1, 0.90))
		_box(root, Vector3(0, 0.52, 0.50), Vector3(0.60, 0.30, 0.035), wood)
		_ice(root, Vector3(0, 0.55, 0.04), Vector2(0.57, 0.69))
		_fish_on_ice(root, Vector3(0, 0.63, 0), 0.9, 1.4)
		for z: float in [-0.23, 0.24]:
			_cylinder(root, Vector3(0.18, 0.63, z), 0.06, 0.015, _mat(Color("d7bd63")))
		_rope(root, Vector3(0, 0.69, -0.33), 0.09, 2)
