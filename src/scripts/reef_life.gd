extends RefCounted
## Deterministic, decorative seabed life. Four shared meshes, batched per dive site.
const Ocean = preload("res://scripts/ocean_config.gd")
const Coral = preload("res://scripts/coral_garden.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const FORMS = ["Seagrass", "Scallop", "SeaStar", "TubeSponge"]
const PER_SITE = [12, 4, 3, 4]
const CORE_PER_SITE = [5, 1, 1, 2]
static var _meshes: Dictionary = {}

static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ReefLife"
	parent.add_child(root)
	var origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var random := RandomNumberGenerator.new()
	random.seed = 813729
	var roots := PackedVector3Array()
	var shared_material: StandardMaterial3D = material()
	var areas: Array = Ocean.exploration_areas()
	for site in range(areas.size()):
		var area: Dictionary = areas[site]
		var center: Vector3 = area.center
		center.y = Ocean.seabed_height(center.x, center.z)
		var region := Node3D.new()
		region.name = "Site%d" % site
		region.position = center - origin
		root.add_child(region)
		for form in range(FORMS.size()):
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.use_colors = true
			batch.mesh = mesh(FORMS[form])
			batch.instance_count = PER_SITE[form]
			for index in range(batch.instance_count):
				# Nine details stay around the landmark; fourteen mark its new rim.
				var point: Vector3 = Geology.detail_point(area, site, index, CORE_PER_SITE[form], random)
				var normal := Vector3(Ocean.seabed_height(point.x - 0.5, point.z) - Ocean.seabed_height(point.x + 0.5, point.z), 1, Ocean.seabed_height(point.x, point.z - 0.5) - Ocean.seabed_height(point.x, point.z + 0.5)).normalized()
				if form == 0 or form == 3:
					normal = Vector3.UP.lerp(normal, 0.45).normalized()
				var basis: Basis = Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, random.randf_range(-PI, PI))
				var size: float = random.randf_range(0.68, 1.12) if form == 0 else random.randf_range(0.45, 0.80)
				batch.set_instance_transform(index, Transform3D(basis.scaled(Vector3.ONE * size), point - center))
				var tint: Color = Color("81ae9b").lerp(Color("b4c5ac"), random.randf()) if form == 0 else Color("d3b5a2").lerp(Color("c3a7bf"), random.randf())
				batch.set_instance_color(index, tint)
				roots.append(point - origin)
			var visual := MultiMeshInstance3D.new()
			visual.name = FORMS[form]
			if form == 0:
				visual.set_meta("harvestable_plant",true)
			visual.multimesh = batch
			visual.material_override = shared_material
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.visibility_range_end = 110.0
			visual.visibility_range_end_margin = 12.0
			region.add_child(visual)
	root.set_meta("site_count", Ocean.DIVE_SITES.size())
	root.set_meta("instance_count", roots.size())
	root.set_meta("root_positions", roots)
	root.set_meta("draw_batches", Ocean.DIVE_SITES.size() * FORMS.size())
	root.set_meta("forms", PackedStringArray(FORMS))
	root.set_meta("decorative_only", true)
	root.set_meta("no_collision", true)
	root.set_meta("distribution", "9 core / 14 outer ring per site")
	return root

static func material() -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.vertex_color_use_as_albedo = true
	result.roughness = 0.82
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result

static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"Seagrass": _grass(surface)
		"Scallop":
			surface.append_from(shell_valve_mesh(), 0, Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3(0, 0.22, 0)))
			surface.append_from(shell_valve_mesh(), 0, Transform3D(Basis(Vector3.RIGHT, -0.26), Vector3(0, 0.22, 0)))
		"SeaStar": _star(surface)
		"TubeSponge": _sponge(surface)
		_:
			push_error("Unknown reef-life mesh: " + kind)
			return ArrayMesh.new()
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	_meshes[kind] = result
	return result

static func _grass(surface: SurfaceTool) -> void:
	for leaf in range(9):
		var angle: float = float(leaf) * 2.399963
		var height: float = 1.12 + float(leaf % 4) * 0.22
		var lean: float = 0.25 + float(leaf % 3) * 0.16
		var tangent := Vector3(cos(angle), 0, -sin(angle))
		for segment in range(4):
			var a: float = float(segment) / 4.0
			var b: float = float(segment + 1) / 4.0
			var center_a := Vector3(sin(angle) * (0.10 + lean * a * a), height * a, cos(angle) * (0.10 + lean * a * a))
			var center_b := Vector3(sin(angle) * (0.10 + lean * b * b), height * b, cos(angle) * (0.10 + lean * b * b))
			var width_a: Vector3 = tangent * sin(a * PI) * 0.09
			var width_b: Vector3 = tangent * sin(b * PI) * 0.09
			var color: Color = Color("406f64").lerp(Color("a9c49b"), (a + b) * 0.45)
			Coral._triangle(surface, center_a - width_a, center_b - width_b, center_a + Vector3.UP * 0.018, color)
			Coral._triangle(surface, center_b - width_b, center_b + Vector3.UP * 0.018, center_a + Vector3.UP * 0.018, color)
			Coral._triangle(surface, center_a + Vector3.UP * 0.018, center_b + Vector3.UP * 0.018, center_a + width_a, color.lightened(0.13))
			Coral._triangle(surface, center_a + width_a, center_b + Vector3.UP * 0.018, center_b + width_b, color.lightened(0.13))

static func shell_valve_mesh() -> ArrayMesh:
	if _meshes.has("ShellValve"):
		return _meshes.ShellValve
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sector in range(18):
		var a: float = -1.2 + float(sector) * 2.4 / 18.0
		var b: float = -1.2 + float(sector + 1) * 2.4 / 18.0
		for ring in range(4):
			var r0: float = float(ring) / 4.0
			var r1: float = float(ring + 1) / 4.0
			var p: Vector3 = _shell_point(a, r0)
			var q: Vector3 = _shell_point(b, r0)
			var r: Vector3 = _shell_point(a, r1)
			var s: Vector3 = _shell_point(b, r1)
			var color: Color = Color("c697a4").lerp(Color("eee3ce"), float(sector % 3) / 2.0)
			Coral._triangle(surface, p, r, q, color)
			Coral._triangle(surface, q, r, s, color)
	for rib in range(10):
		var angle: float = -1.12 + float(rib) * 2.24 / 9.0
		for ring in range(3):
			var a: Vector3 = _shell_point(angle, 0.12 + float(ring) * 0.28) + Vector3.UP * 0.012
			var b: Vector3 = _shell_point(angle, 0.12 + float(ring + 1) * 0.28) + Vector3.UP * 0.012
			Coral._tube(surface, a, b, 0.012, 0.012, Color("f1e3d1"))
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	_meshes.ShellValve = result
	return result

static func _shell_point(angle: float, radial: float) -> Vector3:
	var radius: float = radial * (1.0 + cos(angle * 13.0) * 0.035)
	return Vector3(sin(angle) * radius, sin(radial * PI) * 0.20 + radial * 0.025, cos(angle) * radius)

static func _star(surface: SurfaceTool) -> void:
	var boundary := PackedVector3Array()
	for index in range(10):
		var angle: float = float(index) * TAU / 10.0
		var radius: float = 0.92 if index % 2 == 0 else 0.38
		boundary.append(Vector3(cos(angle) * radius, 0.04, sin(angle) * radius))
	for index in range(10):
		var a: Vector3 = boundary[index]
		var b: Vector3 = boundary[(index + 1) % 10]
		Coral._triangle(surface, Vector3(0, 0.20, 0), b, a, Color("ce8f6d"))
		Coral._triangle(surface, a, b, Vector3.ZERO, Color("93634f"))
	for arm in range(5):
		var angle: float = float(arm) * TAU / 5.0
		for bump in range(4):
			var radius: float = 0.16 + float(bump) * 0.17
			var center := Vector3(cos(angle) * radius, lerpf(0.20, 0.04, radius / 0.92), sin(angle) * radius)
			for side in range(4):
				var a: float = float(side) * TAU / 4.0
				var b: float = float(side + 1) * TAU / 4.0
				Coral._triangle(surface, center + Vector3(cos(a) * 0.032, 0, sin(a) * 0.032), center + Vector3.UP * 0.04, center + Vector3(cos(b) * 0.032, 0, sin(b) * 0.032), Color("edd3a3"))

static func _sponge(surface: SurfaceTool) -> void:
	for tube in range(5):
		var angle: float = float(tube) * 2.399963
		var distance: float = 0.0 if tube == 0 else 0.48
		var point := Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		var height: float = 0.70 + float(tube % 3) * 0.46
		var color: Color = Color("b6a481").lerp(Color("ac99b9"), float(tube % 3) / 2.0)
		Coral._cup(surface, point, height, 0.22 + float(tube % 2) * 0.05, color)
