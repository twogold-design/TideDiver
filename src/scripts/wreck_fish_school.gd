extends Node3D
## Four distinct sheltered shoals inside the wreck, driven by the game clock.
const ReefArt = preload("res://scripts/reef_fish_art.gd")
const KINDS := ["silver", "squirrel", "snapper", "banner"]
const FISH_COUNT := 300
const BATCH_COUNT := 4
const FISH_PER_BATCH := FISH_COUNT / BATCH_COUNT
const MAX_FISH_SCALE := 0.92
const MESH_RADIUS := 0.50 # Includes the shader's tail sway in every orientation.
const BOUNDARY_MARGIN := 0.60
const DRAW_DISTANCE := 175.0
static var _shared_mesh: ArrayMesh

var _bounds: AABB
var _visuals: Array[MultiMeshInstance3D] = []
var _batches: Array[MultiMesh] = []
var _centers := PackedVector3Array()
var _amplitudes := PackedVector3Array()
var _phases := PackedVector3Array()
var _rates := PackedFloat32Array()
var _scales := PackedFloat32Array()
var _material: ShaderMaterial
var _last_time := -INF

func setup(swim_bounds: AABB, compartments: Array = []) -> void:
	# setup is safe before add_child(), and repeated calls replace the old batches.
	for visual: MultiMeshInstance3D in _visuals:
		remove_child(visual)
		visual.free()
	_visuals.clear()
	_batches.clear()
	_centers.clear()
	_amplitudes.clear()
	_phases.clear()
	_rates.clear()
	_scales.clear()
	_bounds = swim_bounds.abs()
	_last_time = -INF
	name = "WreckFishSchool"
	set_meta("fish_count", 0)
	set_meta("draw_batches", 0)
	set_meta("local_swim_bounds", _bounds)
	# Reject compartment boxes too small for the fish and their turning clearance.
	if minf(_bounds.size.x, minf(_bounds.size.y, _bounds.size.z * 0.5)) <= BOUNDARY_MARGIN * 2.0 + 0.1:
		push_error("WreckFishSchool requires at least 1.3m per swimming dimension.")
		return
	_material = ReefArt.material()
	var batch_bounds: Array[AABB] = []
	for batch_index in range(BATCH_COUNT):
		var zone := AABB(_bounds.position + Vector3(0, 0, _bounds.size.z * 0.5 * float(batch_index % 2)), Vector3(_bounds.size.x, _bounds.size.y, _bounds.size.z * 0.5))
		if compartments.size() == BATCH_COUNT:
			zone = compartments[batch_index]
		var mesh: ArrayMesh = _fish_mesh() if batch_index == 0 else ReefArt.mesh(KINDS[batch_index])
		batch_bounds.append(zone)
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.use_custom_data = true
		batch.mesh = mesh
		batch.instance_count = FISH_PER_BATCH
		var visual := MultiMeshInstance3D.new()
		visual.name = KINDS[batch_index].capitalize() + "Shoal"
		visual.set_meta("species",KINDS[batch_index])
		visual.position = zone.get_center()
		visual.multimesh = batch
		visual.material_override = _material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = DRAW_DISTANCE
		visual.visibility_range_end_margin = 12.0
		visual.custom_aabb = AABB(zone.position - visual.position, zone.size)
		add_child(visual)
		_visuals.append(visual)
		_batches.append(batch)
		for index in range(FISH_PER_BATCH):
			var fish_id: int = batch_index * FISH_PER_BATCH + index
			var seed_value: float = float(fish_id) + 0.5
			var room: Vector3 = zone.size * 0.5 - Vector3.ONE * BOUNDARY_MARGIN
			var amplitude := Vector3(
				minf(room.x * 0.44, 0.50 + 0.30 * fposmod(seed_value * 0.381966, 1.0)),
				minf(room.y * 0.32, 0.14 + 0.16 * fposmod(seed_value * 0.438579, 1.0)),
				minf(room.z * 0.40, 0.65 + 0.55 * fposmod(seed_value * 0.569840, 1.0)))
			var low: Vector3 = zone.position + Vector3.ONE * BOUNDARY_MARGIN + amplitude
			var high: Vector3 = zone.end - Vector3.ONE * BOUNDARY_MARGIN - amplitude
			# Low discrepancy coordinates fill the hold without a visible lattice or clumps.
			_centers.append(Vector3(
				lerpf(low.x, high.x, fposmod(seed_value * 0.754877666, 1.0)),
				lerpf(low.y, high.y, fposmod(seed_value * 0.569840296, 1.0)),
				lerpf(low.z, high.z, fposmod(seed_value * 0.438579021, 1.0))))
			_amplitudes.append(amplitude)
			_phases.append(Vector3(
				fposmod(seed_value * 0.618034, 1.0),
				fposmod(seed_value * 0.414214, 1.0),
				fposmod(seed_value * 0.732051, 1.0)) * TAU)
			_rates.append((0.17 + 0.07 * fposmod(seed_value * 0.357143, 1.0))*[1.0,0.62,0.85,0.70][batch_index])
			_scales.append(lerpf(0.38 if batch_index == 0 else 0.64,0.64 if batch_index == 0 else MAX_FISH_SCALE,fposmod(seed_value * 0.618034, 1.0)))
			batch.set_instance_color(index, Color.WHITE.lerp(Color("b6cfce"),fposmod(seed_value * 0.276393, 1.0)*.12))
			batch.set_instance_custom_data(index, Color(fposmod(seed_value * 0.618034, 1.0), fposmod(seed_value * 0.414214, 1.0), 0, 1))
	_update_instances(0.0)
	set_meta("fish_count", FISH_COUNT)
	set_meta("draw_batches", BATCH_COUNT)
	set_meta("species",PackedStringArray(KINDS))
	set_meta("batch_local_bounds", batch_bounds)
	set_meta("max_fish_radius", MESH_RADIUS * MAX_FISH_SCALE)
	set_meta("no_collision", true)
	set_meta("decorative_only", true)
	set_meta("external_clock_only", true)

func animate(time: float, viewer: Vector3) -> void:
	var center: Vector3 = global_transform * _bounds.get_center() if is_inside_tree() else transform * _bounds.get_center()
	visible = viewer.distance_to(center) < 185.0
	if not visible or _material == null:
		return
	_material.set_shader_parameter("school_clock", time)
	if time != _last_time:
		_update_instances(time)

func _update_instances(time: float) -> void:
	for fish_id in range(_centers.size()):
		var rate: float = _rates[fish_id]
		var phase: Vector3 = _phases[fish_id] + Vector3(time * rate, time * rate * 0.63, time * rate * 0.83)
		var amplitude: Vector3 = _amplitudes[fish_id]
		var point: Vector3 = _centers[fish_id] + Vector3(sin(phase.x), sin(phase.y), sin(phase.z)) * amplitude
		var velocity := Vector3(cos(phase.x) * amplitude.x, cos(phase.y) * amplitude.y * 0.63, cos(phase.z) * amplitude.z * 0.83)
		# The gentle vertical drift does not turn a grazing shoal into nose-up fish.
		var pitch_limit: float = Vector2(velocity.x, velocity.z).length() * 0.32
		velocity.y = clampf(velocity.y, -pitch_limit, pitch_limit)
		if velocity.length_squared() < 0.000001:
			velocity = Vector3.FORWARD
		var basis: Basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
		basis = basis.scaled(Vector3.ONE * _scales[fish_id])
		var batch_index: int = fish_id / FISH_PER_BATCH
		_batches[batch_index].set_instance_transform(fish_id % FISH_PER_BATCH, Transform3D(basis, point - _visuals[batch_index].position))
	_last_time = time

static func _fish_mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := PackedVector3Array([
		Vector3(0.064, 0.075, -0.255), Vector3(0.102, 0.135, -0.065),
		Vector3(0.065, 0.085, 0.135), Vector3(0.022, 0.032, 0.255)])
	for ring in range(rings.size() - 1):
		for side in range(8):
			var a: Vector3 = _ring_vertex(rings[ring], side)
			var b: Vector3 = _ring_vertex(rings[ring], side + 1)
			var c: Vector3 = _ring_vertex(rings[ring + 1], side)
			var d: Vector3 = _ring_vertex(rings[ring + 1], side + 1)
			var tint: Color = Color("a7c5d7")
			var height: float = sin((float(side) + 0.5) * TAU / 8.0)
			if height > 0.3:
				tint = Color("527c9f").lerp(Color("779fbd"), 1.0 - height)
			elif height < -0.3:
				tint = Color("dce8ed")
			_triangle(surface, a, b, c, tint)
			_triangle(surface, b, d, c, tint)
	for side in range(8):
		_triangle(surface, Vector3(0, 0.002, -0.34), _ring_vertex(rings[0], side + 1), _ring_vertex(rings[0], side), Color("9ab8cb"))
		_triangle(surface, Vector3(0, 0, 0.27), _ring_vertex(rings[3], side), _ring_vertex(rings[3], side + 1), Color("83adc4"))
	var fin := Color("80aeca")
	_triangle(surface, Vector3(0, 0, 0.24), Vector3(0, 0.19, 0.45), Vector3(0, 0.025, 0.365), fin)
	_triangle(surface, Vector3(0, 0, 0.24), Vector3(0, -0.19, 0.45), Vector3(0, -0.025, 0.365), fin)
	_triangle(surface, Vector3(0, 0.11, -0.14), Vector3(0, 0.235, 0.035), Vector3(0, 0.075, 0.18), fin)
	_triangle(surface, Vector3(0, -0.105, -0.03), Vector3(0, -0.18, 0.12), Vector3(0, -0.06, 0.185), fin)
	for side: float in [-1.0, 1.0]:
		_triangle(surface, Vector3(side * 0.09, -0.02, -0.12), Vector3(side * 0.23, -0.07, 0.055), Vector3(side * 0.07, -0.035, 0.085), fin)
		# A long pale lateral scale and a dark eye keep the tiny silhouette readable.
		var a := Vector3(side * 0.081, 0.005, -0.21)
		var b := Vector3(side * 0.106, 0.025, -0.065)
		var c := Vector3(side * 0.068, 0.0, 0.14)
		var d := Vector3(side * 0.104, -0.01, -0.065)
		_triangle(surface, a, b, d, Color("eaf4f4"))
		_triangle(surface, b, c, d, Color("d4e9f0"))
		var eye := Vector3(side * 0.068, 0.026, -0.252)
		_triangle(surface, eye + Vector3(0, 0.018, 0), eye + Vector3(0, 0, -0.02), eye + Vector3(0, -0.018, 0), Color("173c50"))
		_triangle(surface, eye + Vector3(0, 0.018, 0), eye + Vector3(0, -0.018, 0), eye + Vector3(0, 0, 0.02), Color("173c50"))
		_triangle(surface, eye + Vector3(side * 0.001, 0.012, -0.006), eye + Vector3(side * 0.001, 0.004, -0.012), eye + Vector3(side * 0.001, 0.002, -0.004), Color("e2f2f4"))
	surface.generate_normals()
	_shared_mesh = surface.commit()
	return _shared_mesh

static func _ring_vertex(ring: Vector3, side: int) -> Vector3:
	var angle: float = float(side) * TAU / 8.0
	return Vector3(cos(angle) * ring.x, sin(angle) * ring.y, ring.z)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	for vertex: Vector3 in [a, b, c]:
		surface.add_vertex(vertex)
