extends RefCounted
## A continuous reef garden, batched into four shared, original coral meshes.
const Ocean = preload("res://scripts/ocean_config.gd")
const FORM_NAMES = ["Staghorn", "TableCoral", "SeaFan", "BrainCoral"]
const PALETTE = [Color("ef9277"), Color("ecc273"), Color("bc8bd1"), Color("cf789d"), Color("8ec6af"), Color("d7c8a7"), Color("65b9b6"), Color("d88765")]
const FOOTPRINT = Rect2(-45.0, -43.5, 90.0, 75.0)

static func build(parent: Node3D) -> void:
	var garden := Node3D.new()
	garden.name = "CoralGarden"
	parent.add_child(garden)
	var origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var random := RandomNumberGenerator.new()
	random.seed = 73513
	var transforms: Array[Array] = [[], [], [], []]
	var colors: Array[Array] = [[], [], [], []]
	var positions := PackedVector3Array()
	for row in range(10):
		for column in range(18):
			var x: float = (float(column) - 8.5) * 4.8 + random.randf_range(-0.8, 0.8)
			var z: float = (float(row) - 4.5) * 7.2 - 6.0 + random.randf_range(-1.25, 1.25)
			# A seven-metre winding sand lane remains open between the living banks.
			if absf(x - sin((z + 6.0) * 0.055) * 6.0) < 7.0:
				continue
			var point := Vector3(x, Ocean.seabed_height(origin.x + x, origin.z + z) - origin.y, z)
			var form: int = posmod(column + row * 3, FORM_NAMES.size())
			var yaw: float = random.randf_range(-PI, PI)
			var size: float = random.randf_range(0.92, 1.22)
			var scale := Vector3(size, random.randf_range(1.05, 1.42), size)
			transforms[form].append(Transform3D(Basis(Vector3.UP, yaw).scaled(scale), point))
			colors[form].append(PALETTE[posmod(column + row * 3 + int(column / 4), PALETTE.size())])
			positions.append(point)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	# Gentle local colour keeps the reef readable through the blue water.
	material.emission_enabled = true
	material.emission = Color("9caa9a")
	material.emission_energy_multiplier = 0.12
	for form in range(FORM_NAMES.size()):
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = _coral_mesh(form)
		batch.instance_count = transforms[form].size()
		for index in range(batch.instance_count):
			batch.set_instance_transform(index, transforms[form][index])
			batch.set_instance_color(index, colors[form][index])
		var visual := MultiMeshInstance3D.new()
		visual.name = FORM_NAMES[form]
		visual.multimesh = batch
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 175.0
		visual.visibility_range_end_margin = 20.0
		garden.add_child(visual)
	garden.set_meta("patch_count", positions.size())
	garden.set_meta("footprint", FOOTPRINT)
	garden.set_meta("patch_positions", positions)
	garden.set_meta("forms", PackedStringArray(FORM_NAMES))
	garden.set_meta("channel_width", 7.0)
	garden.set_meta("draw_batches", FORM_NAMES.size())

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(vertex)

static func _tube(surface: SurfaceTool, start: Vector3, end: Vector3, bottom: float, top: float, color: Color) -> void:
	var direction: Vector3 = (end - start).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD if absf(direction.y) > 0.9 else Vector3.UP).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	for index in range(6):
		var a: float = float(index) * TAU / 6.0
		var b: float = float(index + 1) * TAU / 6.0
		var radial_a: Vector3 = side * cos(a) + up * sin(a)
		var radial_b: Vector3 = side * cos(b) + up * sin(b)
		var p: Vector3 = start + radial_a * bottom
		var q: Vector3 = start + radial_b * bottom
		var r: Vector3 = end + radial_a * top
		var s: Vector3 = end + radial_b * top
		_triangle(surface, p, r, q, color)
		_triangle(surface, q, r, s, color)
		_triangle(surface, end, s, r, color.lightened(0.12))

static func _dome(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	for ring in range(6):
		var latitude_a: float = float(ring) * PI / 12.0
		var latitude_b: float = float(ring + 1) * PI / 12.0
		for index in range(14):
			var a: float = float(index) * TAU / 14.0
			var b: float = float(index + 1) * TAU / 14.0
			var p: Vector3 = center + Vector3(cos(a) * cos(latitude_a), sin(latitude_a), sin(a) * cos(latitude_a)) * size
			var q: Vector3 = center + Vector3(cos(b) * cos(latitude_a), sin(latitude_a), sin(b) * cos(latitude_a)) * size
			var r: Vector3 = center + Vector3(cos(a) * cos(latitude_b), sin(latitude_b), sin(a) * cos(latitude_b)) * size
			var s: Vector3 = center + Vector3(cos(b) * cos(latitude_b), sin(latitude_b), sin(b) * cos(latitude_b)) * size
			_triangle(surface, p, q, r, color)
			_triangle(surface, q, s, r, color)

static func _plate(surface: SurfaceTool, center: Vector3, radius: float) -> void:
	for index in range(24):
		var a: float = float(index) * TAU / 24.0
		var b: float = float(index + 1) * TAU / 24.0
		var ra: float = radius * (1.0 + sin(a * 5.0) * 0.07)
		var rb: float = radius * (1.0 + sin(b * 5.0) * 0.07)
		var rim_a: Vector3 = center + Vector3(cos(a) * ra, 0.04 + sin(a * 3.0) * 0.06, sin(a) * ra)
		var rim_b: Vector3 = center + Vector3(cos(b) * rb, 0.04 + sin(b * 3.0) * 0.06, sin(b) * rb)
		var inner_a: Vector3 = center + Vector3(cos(a) * ra * 0.78, 0.22, sin(a) * ra * 0.78)
		var inner_b: Vector3 = center + Vector3(cos(b) * rb * 0.78, 0.22, sin(b) * rb * 0.78)
		_triangle(surface, center + Vector3.UP * 0.23, inner_a, inner_b, Color("e5e5df"))
		_triangle(surface, inner_a, rim_a, inner_b, Color("ededdf"))
		_triangle(surface, rim_a, rim_b, inner_b, Color("f6efe2"))
		_triangle(surface, rim_a, center - Vector3.UP * 0.10, rim_b, Color("929c92"))
		_tube(surface, inner_a, rim_a, 0.035, 0.035, Color.WHITE)

static func _coral_mesh(form: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match form:
		0:
			_tube(surface, Vector3.ZERO, Vector3(0, 1.5, 0), 0.20, 0.14, Color("aeb7a8"))
			for arm in range(7):
				var angle: float = float(arm) * TAU / 7.0
				var elbow := Vector3(cos(angle) * 0.82, 1.35 + float(arm % 3) * 0.22, sin(angle) * 0.82)
				var tip := Vector3(cos(angle) * 1.75, 2.7 + float(arm % 2) * 0.55, sin(angle) * 1.75)
				_tube(surface, Vector3(0, 0.45, 0), elbow, 0.14, 0.10, Color("c8cec2"))
				_tube(surface, elbow, tip, 0.10, 0.045, Color("eeeeeb"))
				for fork in range(2):
					var join: Vector3 = elbow.lerp(tip, 0.30 + float(fork) * 0.34)
					var end: Vector3 = join + Vector3(cos(angle + 0.8) * 0.65, 0.8, sin(angle + 0.8) * 0.65)
					_tube(surface, join, end, 0.065, 0.025, Color.WHITE)
		1:
			_tube(surface, Vector3.ZERO, Vector3(0, 2.0, 0), 0.30, 0.18, Color("aeb7a8"))
			_plate(surface, Vector3(0, 2.0, 0), 2.45)
			_tube(surface, Vector3(0, 0.1, 0), Vector3(-0.85, 0.95, 0.4), 0.16, 0.12, Color("bfc7b8"))
			_plate(surface, Vector3(-0.85, 0.95, 0.4), 1.40)
			_plate(surface, Vector3(0.75, 1.35, -0.65), 1.15)
		2:
			_tube(surface, Vector3.ZERO, Vector3(0, 0.7, 0), 0.14, 0.10, Color("b4beb5"))
			for spoke in range(11):
				var angle: float = -1.10 + float(spoke) * 0.22
				var tip := Vector3(sin(angle) * 2.8, 0.7 + cos(angle) * 2.8, sin(angle * 2.0) * 0.12)
				_tube(surface, Vector3(0, 0.65, 0), tip, 0.075, 0.025, Color("ededed"))
				if spoke == 10:
					continue
				for tier in range(1, 5):
					var radius: float = 0.65 + float(tier) * 0.43
					var from := Vector3(sin(angle) * radius, 0.7 + cos(angle) * radius, sin(angle * 2.0) * 0.12)
					var to := Vector3(sin(angle + 0.22) * radius, 0.7 + cos(angle + 0.22) * radius, sin((angle + 0.22) * 2.0) * 0.12)
					_tube(surface, from, to, 0.035, 0.035, Color("d7dfd9"))
		3:
			_dome(surface, Vector3.ZERO, Vector3(1.75, 1.55, 1.65), Color("9cae9c"))
			for band in range(9):
				var longitude: float = float(band) * TAU / 9.0
				for step in range(12):
					var a: float = float(step) * PI / 24.0
					var b: float = float(step + 1) * PI / 24.0
					var angle_a: float = longitude + sin(a * 9.0 + band) * 0.10
					var angle_b: float = longitude + sin(b * 9.0 + band) * 0.10
					var start := Vector3(cos(angle_a) * cos(a) * 1.78, sin(a) * 1.58, sin(angle_a) * cos(a) * 1.68)
					var end := Vector3(cos(angle_b) * cos(b) * 1.78, sin(b) * 1.58, sin(angle_b) * cos(b) * 1.68)
					_tube(surface, start, end, 0.065, 0.065, Color("eff0d9"))
			_dome(surface, Vector3(1.05, 0.0, 0.7), Vector3(0.85, 0.72, 0.80), Color("b5c5ac"))
	surface.generate_normals()
	return surface.commit()
