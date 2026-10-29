extends RefCounted
## Shared, texture-free seabed and eroded stone assets for the web renderer.
## Decorative geology never changes the shared terrain or adds collision.
const Ocean = preload("res://scripts/ocean_config.gd")
const DETAIL_PER_FORM := 24
const DETAIL_FORMS := 3
const DETAIL_RANGE := 110.0
static var _sand: ShaderMaterial
static var _rock: ShaderMaterial
static var _meshes: Dictionary = {}
static var _pebbles: Dictionary = {}

static func sand_material() -> ShaderMaterial:
	if _sand != null:
		return _sand
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 ground_position;
varying vec3 ground_normal;
uniform vec2 canyon_center;
uniform float canyon_half_length;
uniform float canyon_bend_amplitude;
uniform float canyon_bend_frequency;
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise21(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}
void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec2 p = ground_position.xz;
	float distance_to_eye = distance(CAMERA_POSITION_WORLD, ground_position);
	float bed = noise21(p * 0.075);
	float dune = noise21(p * 0.52);
	float slope = 1.0 - clamp(abs(ground_normal.y), 0.0, 1.0);
	float rock_mask = smoothstep(0.13, 0.49, slope + (bed - 0.5) * 0.17);
	// The fine layers fade before their wavelength becomes smaller than a pixel.
	float ripple_detail = (1.0 - smoothstep(12.0, 43.0, distance_to_eye));
	float grain_detail = 1.0 - smoothstep(2.0, 9.0, distance_to_eye);
	float phase = p.x * 16.5 + p.y * 6.2 + sin(p.y * 0.72) * 1.6 + dune * 2.5;
	float ripple = sin(phase) * 0.5 + 0.5;
	float ripple_amount = 0.35 + 0.65 * noise21(p * 0.23 + vec2(9.0, 3.0));
	float ripple_contrast = (ripple - 0.5) * 0.040 * ripple_detail * ripple_amount;
	float grain = (noise21(p * 65.0) - 0.5) * 0.042 * grain_detail;
	vec3 sand = mix(vec3(0.53, 0.53, 0.43), vec3(0.69, 0.66, 0.53), bed * 0.65 + dune * 0.35);
	sand += ripple_contrast + grain;
	float band = sin(ground_position.y * 2.35 + noise21(p * 0.18) * 2.0) * 0.5 + 0.5;
	vec3 stone = mix(vec3(0.28, 0.34, 0.34), vec3(0.45, 0.46, 0.40), band * 0.48 + dune * 0.52);
	ALBEDO = mix(sand, stone, rock_mask * 0.82);
	// One continuous surface: sediment blends into eroded walls per fragment,
	// eliminating the old four-metre stair-step edge of the bank overlay mesh.
	float along = abs(p.y-canyon_center.y);
	float center_x = canyon_center.x+canyon_bend_amplitude*sin((p.y-canyon_center.y)*canyon_bend_frequency);
	float across = abs(p.x-center_x);
	float canyon = (1.0-smoothstep(canyon_half_length-28.0,canyon_half_length+8.0,along))*(1.0-smoothstep(55.0,68.0,across));
	if (canyon > 0.001) {
		float erosion = noise21(vec2(p.y*0.075,ground_position.y*0.10));
		float layers = ground_position.y*0.68 + sin(p.y*0.045)*1.5 + (erosion-0.5)*2.8;
		float strata = sin(layers)*0.5+0.5;
		float seam = 1.0-smoothstep(0.025,0.10+fwidth(layers),abs(sin(layers*0.5)));
		vec3 limestone = mix(vec3(0.38,0.49,0.49),vec3(0.64,0.66,0.56),erosion*0.60+strata*0.40);
		limestone *= 1.0-seam*0.065;
		float weathering = noise21(vec2(p.y*0.41,ground_position.y*0.32));
		limestone *= 0.94+weathering*0.12;
		float sediment = (1.0-smoothstep(0.10,0.38,slope))*(0.78+bed*0.22);
		vec3 canyon_sand = mix(vec3(0.58,0.63,0.56),vec3(0.71,0.73,0.63),bed)+ripple_contrast+grain;
		vec3 canyon_color = mix(limestone,canyon_sand,sediment);
		ALBEDO = mix(ALBEDO,canyon_color,canyon);
	}
	ROUGHNESS = 0.96;
	SPECULAR = 0.16;
	// Tiny lighting relief only; vertices and the collision surface stay exact.
	vec3 bump = vec3(cos(phase) * 0.026, 0.0, cos(phase) * 0.011) * ripple_detail * ripple_amount * (1.0 - rock_mask);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);
}
"""
	_sand = ShaderMaterial.new()
	_sand.shader = shader
	_sand.set_shader_parameter("canyon_center",Vector2(Ocean.CANYON_CENTER.x,Ocean.CANYON_CENTER.z))
	_sand.set_shader_parameter("canyon_half_length",Ocean.CANYON_HALF_LENGTH)
	_sand.set_shader_parameter("canyon_bend_amplitude",Ocean.CANYON_BEND_AMPLITUDE)
	_sand.set_shader_parameter("canyon_bend_frequency",Ocean.CANYON_BEND_FREQUENCY)
	return _sand

static func rock_material() -> Material:
	if _rock != null:
		return _rock
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 stone_position;
varying vec3 stone_normal;
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise31(vec3 p) {
	vec3 c = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(c), hash31(c + vec3(1, 0, 0)), f.x),
		mix(hash31(c + vec3(0, 1, 0)), hash31(c + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(c + vec3(0, 0, 1)), hash31(c + vec3(1, 0, 1)), f.x),
		mix(hash31(c + vec3(0, 1, 1)), hash31(c + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	stone_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	stone_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 p = stone_position;
	float macro = noise31(p * 0.72);
	float grain = noise31(p * 7.0);
	float nearby = 1.0 - smoothstep(8.0, 32.0, distance(CAMERA_POSITION_WORLD, p));
	float strata = sin(p.y * 3.1 + noise31(p * 0.30) * 2.6) * 0.5 + 0.5;
	float seam = abs(sin(p.x * 0.75 + p.z * 0.68 + macro * 5.0));
	float crack = (1.0 - smoothstep(0.015, 0.055 + fwidth(seam), seam)) * nearby;
	vec3 grey = mix(vec3(0.44, 0.47, 0.43), vec3(0.70, 0.69, 0.59), macro * 0.50 + strata * 0.50);
	float upper = smoothstep(0.18, 0.80, stone_normal.y);
	float algae = smoothstep(0.38, 0.72, macro) * upper * 0.20;
	grey = mix(grey, vec3(0.36, 0.46, 0.36), algae);
	ALBEDO = COLOR.rgb * grey * (1.0 - crack * 0.14) + vec3((grain - 0.5) * 0.035 * nearby);
	ROUGHNESS = 0.95;
	SPECULAR = 0.14;
}
"""
	_rock = ShaderMaterial.new()
	_rock.shader = shader
	return _rock

static func rock_mesh(seed_value: int = 0) -> ArrayMesh:
	# A small finite set lets all outcrops and debris share GPU resources.
	var variant: int = posmod(seed_value, 7)
	if not _meshes.has(variant):
		_meshes[variant] = _eroded_mesh(variant, 24, 13)
	return _meshes[variant]

static func _eroded_mesh(variant: int, segments: int, rings: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var phase: float = float(variant) * 1.731
	for row in range(rings + 1):
		var t: float = float(row) / float(rings)
		var latitude: float = t * PI
		var y: float = cos(latitude)
		var ring_width: float = sin(latitude)
		for column in range(segments + 1):
			var a: float = float(column) * TAU / float(segments)
			var erosion: float = 0.14 * sin(a * 3.0 + phase + y * 1.7) + 0.065 * cos(a * 5.0 - phase * 0.7 + y * 3.1)
			var strata: float = 0.045 * sin(y * 13.0 + sin(a * 2.0 + phase) * 0.8 + phase)
			var notch: float = 0.12 * pow(maxf(0.0, cos(a * 2.0 + phase - y * 2.0)), 5.0)
			var radial: float = ring_width * (0.96 + erosion + strata - notch)
			var point := Vector3(cos(a) * radial * (0.91 + 0.09 * sin(phase)), y * (0.80 + 0.07 * cos(phase)), sin(a) * radial * (0.88 + 0.10 * cos(phase)))
			point.x += ring_width * 0.065 * sin(y * 2.7 + phase)
			point.z += ring_width * 0.045 * cos(y * 4.1 - phase)
			# The lower face is worn flat; upper rings retain asymmetric shoulders.
			point.y = maxf(point.y, -0.70)
			point.y += ring_width * 0.035 * sin(a * 3.0 + phase)
			vertices.append(point)
			normals.append(Vector3.ZERO)
			var tone: float = clampf(0.42 + y * 0.18 + erosion * 0.65, 0.0, 1.0)
			colors.append(Color("84928c").lerp(Color("d4d0bb"), tone))
	for row in range(rings):
		for column in range(segments):
			var a: int = row * (segments + 1) + column
			var b: int = a + segments + 1
			for tri: Array in [[a, a + 1, b], [a + 1, b + 1, b]]:
				if row == 0 and tri[0] == a:
					continue
				if row == rings - 1 and tri[0] == a + 1:
					continue
				var cross: Vector3 = (vertices[tri[1]] - vertices[tri[0]]).cross(vertices[tri[2]] - vertices[tri[0]])
				if cross.length_squared() < 0.0000001:
					continue
				# Godot's clockwise front faces use the reverse of the normal cross.
				indices.append_array(PackedInt32Array([tri[0], tri[2], tri[1]]))
				for index: int in tri:
					normals[index] += cross
	for row in range(rings + 1):
		var first: int = row * (segments + 1)
		var last: int = first + segments
		var seam: Vector3 = normals[first] + normals[last]
		normals[first] = seam
		normals[last] = seam
	for index in range(normals.size()):
		normals[index] = normals[index].normalized() if normals[index].length_squared() > 0.000001 else vertices[index].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func decorate(parent: Node3D) -> void:
	var geology := Node3D.new()
	geology.name = "OceanGeology"
	parent.add_child(geology)
	var parent_origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var random := RandomNumberGenerator.new()
	random.seed = 641390
	var roots := PackedVector3Array()
	var stonefish_rocks: Array[Dictionary] = []
	var areas: Array = Ocean.exploration_areas()
	for site in range(areas.size()):
		var area: Dictionary = areas[site]
		var center: Vector3 = area.center
		var local_center := Vector3(center.x, Ocean.seabed_height(center.x, center.z), center.z) - parent_origin
		for form in range(DETAIL_FORMS):
			if not _pebbles.has(form):
				_pebbles[form] = _eroded_mesh(form + 2, 12, 6)
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = _pebbles[form]
			multi.instance_count = DETAIL_PER_FORM
			for index in range(DETAIL_PER_FORM):
				# Keep ten stones near the original landmark, spread fourteen into
				# the new exploration ring, without increasing the instance budget.
				var point: Vector3 = detail_point(area, site, index, 10, random)
				var x: float = point.x
				var z: float = point.z
				var floor_y: float = Ocean.seabed_height(x, z)
				var extent: float = random.randf_range(0.17, 0.66)
				var size := Vector3(extent, extent * random.randf_range(0.32, 0.65), extent * random.randf_range(0.70, 1.40))
				var yaw: float = random.randf_range(-PI, PI)
				var dx: float = (Ocean.seabed_height(x + 0.3, z) - Ocean.seabed_height(x - 0.3, z)) / 0.6
				var dz: float = (Ocean.seabed_height(x, z + 0.3) - Ocean.seabed_height(x, z - 0.3)) / 0.6
				var normal := Vector3(-dx, 1.0, -dz).normalized()
				var basis := (Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, yaw)).scaled(size)
				# The flattened base follows the slope and is partly buried in sand.
				var root := Vector3(x, floor_y, z)
				var position := root + normal * size.y * 0.41 - parent_origin - local_center
				multi.set_instance_transform(index, Transform3D(basis, position))
				multi.set_instance_color(index, Color("b7b4a0").lerp(Color("d9d2b8"), random.randf()))
				roots.append(root)
				var world_pose := Transform3D(basis,position+parent_origin+local_center)
				stonefish_rocks.append({"bounds":world_pose*multi.mesh.get_aabb(),"position":root,"site":site})
			var batch := MultiMeshInstance3D.new()
			batch.name = "Site%dPebbles%d" % [site, form]
			batch.position = local_center
			batch.multimesh = multi
			batch.material_override = rock_material()
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.visibility_range_end = DETAIL_RANGE
			batch.visibility_range_end_margin = 12.0
			geology.add_child(batch)
	geology.set_meta("detail_count", roots.size())
	geology.set_meta("draw_batches", Ocean.DIVE_SITES.size() * DETAIL_FORMS)
	geology.set_meta("ground_roots", roots)
	geology.set_meta("stonefish_rocks",stonefish_rocks)
	geology.set_meta("collision_unchanged", true)
	geology.set_meta("distribution", "10 core / 14 outer ring per form")

## Shared placement for seabed detail. Rejection rotates a candidate while retaining
## its chosen radial band, so protected approaches cannot push it outside its area.
static func detail_point(area: Dictionary, site: int, index: int, core_count: int, random: RandomNumberGenerator) -> Vector3:
	var center: Vector3 = area.center
	var radius: float = float(area.radius)
	var core_radius: float = float(area.core_radius)
	var core_inner: float = 23.0 if site == 1 else 11.0
	var inner: float = core_inner if index < core_count else maxf(core_radius + 3.0, radius * 0.64)
	var outer: float = core_radius * 0.94 if index < core_count else radius * 0.96
	var distance: float = sqrt(lerpf(inner * inner, outer * outer, random.randf()))
	var angle: float = random.randf_range(-PI, PI)
	var point := center
	for attempt in range(48):
		point = center + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		if _detail_clear(point, center, site):
			break
		angle += 2.3999632297
	point.y = Ocean.seabed_height(point.x, point.z)
	return point

static func _detail_clear(point: Vector3, center: Vector3, site: int) -> bool:
	if Ocean.seabed_height(point.x,point.z) > -6.0:
		return false
	var entry: Vector3 = Ocean.DIVE_SITES[site].origin + Vector3(0, 0, 25)
	var p := Vector2(point.x, point.z)
	var a := Vector2(entry.x, entry.z)
	var b := Vector2(center.x, center.z)
	if p.distance_to(a) < 14.0:
		return false
	if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < 8.5:
		return false
	if site == 1 and absf(point.z - Ocean.CANYON_CENTER.z) < Ocean.CANYON_HALF_LENGTH:
		if absf(point.x - Ocean.canyon_center_x(point.z)) < 20.0:
			return false
	if Ocean.DIVE_SITES[site].id == "merchant_wreck" and absf(point.x - 310.0) < 12.0 and absf(point.z + 133.0) < 22.0:
		return false
	if Ocean.DIVE_SITES[site].id == "amber_reef":
		var lane: float = -180.0 + sin((point.z - 135.0 + 6.0) * 0.055) * 6.0
		if absf(point.x - lane) < 8.5:
			return false
	return true
