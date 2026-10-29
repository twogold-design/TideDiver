class_name TidalCanyonArt
extends Node3D
## Exposed canyon banks and current tracers; the shared seabed supplies all collision.
const Ocean = preload("res://scripts/ocean_config.gd")
const Coral = preload("res://scripts/coral_garden.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const CENTER_Z := Ocean.CANYON_CENTER.z
const LENGTH := Ocean.CANYON_HALF_LENGTH * 2.0
const TRACE_COUNT := 480
const TRACE_TRAVEL := 32.0
const VIEW_DISTANCE := 540.0
var current_material: ShaderMaterial

static func build(parent: Node3D) -> Node3D:
	var canyon := TidalCanyonArt.new()
	canyon.name = "TidalCanyon"
	parent.add_child(canyon)
	var origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var bank_roots := PackedVector3Array()
	var rock_transforms: Array[Transform3D] = []
	var fan_transforms: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	var fan_colors: Array[Color] = []
	var random := RandomNumberGenerator.new()
	random.seed = 492311
	var row_count: int = int(ceil(LENGTH / 10.0))
	for bank: float in [-1.0, 1.0]:
		for row in range(row_count):
			var z: float = CENTER_Z - Ocean.CANYON_HALF_LENGTH + (float(row) + 0.5) * LENGTH / float(row_count)
			for tier in range(3):
				var x: float = Ocean.canyon_center_x(z) + bank * (25.0 + float(tier) * 14.0 + random.randf_range(-1.4, 1.4))
				var world_root := Vector3(x, Ocean.seabed_height(x, z), z)
				var root: Vector3 = world_root - origin
				var size := Vector3(random.randf_range(3.0, 5.8), random.randf_range(1.2, 3.4), random.randf_range(4.0, 6.8))
				var normal := Vector3(Ocean.seabed_height(x-1.0,z)-Ocean.seabed_height(x+1.0,z),2.0,Ocean.seabed_height(x,z-1.0)-Ocean.seabed_height(x,z+1.0)).normalized()
				# Loose shelves belong on ledges. A boulder on the near-vertical
				# ridge face reads as a floating prop even when its centre touches it.
				if normal.y < 0.5:
					continue
				var bank_basis := Basis(Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP,normal),0.55)) * Basis(Vector3.UP,random.randf_range(-0.3,0.3))
				rock_transforms.append(Transform3D(bank_basis.scaled(size), root - normal * size.y * 0.18))
				var stone_color := Color("637b7b").lerp(Color("a3a78c"),random.randf())
				rock_colors.append(stone_color.lerp(Color("b5ae94"),smoothstep(-2.0,8.0,world_root.y)*0.5))
				bank_roots.append(root)
			if row % 2 == 0:
				var x: float = Ocean.canyon_center_x(z) + bank * 29.0
				var world_root := Vector3(x, Ocean.seabed_height(x,z), z)
				# Keep the entire fan below the tide line, including its tallest tips.
				if world_root.y < -4.0:
					var root: Vector3 = world_root - origin
					fan_transforms.append(Transform3D(Basis(Vector3.UP, random.randf_range(-PI, PI)).scaled(Vector3.ONE * random.randf_range(0.7, 1.0)), root))
					fan_colors.append(Color("a8ad91").lerp(Color("b3929b"), random.randf()))
					bank_roots.append(root)
	var strata := MeshInstance3D.new()
	strata.name = "LayeredBanks"
	strata.mesh = _bank_mesh(origin)
	strata.material_override = Geology.rock_material()
	strata.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strata.visibility_range_end = VIEW_DISTANCE
	strata.visibility_range_end_margin = 35.0
	canyon.add_child(strata)
	var rock: ArrayMesh = Geology.rock_mesh(2)
	_batch(canyon, "RockShelves", rock, rock_transforms, rock_colors, Geology.rock_material())
	_batch(canyon, "SparseSeaFans", Coral._coral_mesh(2), fan_transforms, fan_colors, Coral.material())
	canyon._build_current(origin)
	canyon.set_meta("world_center", Vector3(Ocean.canyon_center_x(CENTER_Z), Ocean.seabed_height(Ocean.canyon_center_x(CENTER_Z), CENTER_Z), CENTER_Z))
	canyon.set_meta("length", LENGTH)
	canyon.set_meta("flow_direction", Ocean.canyon_tangent(CENTER_Z))
	canyon.set_meta("channel_width", Ocean.CANYON_FLOOR_HALF_WIDTH * 2.0)
	canyon.set_meta("bank_span", Ocean.CANYON_BANK_HALF_WIDTH * 2.0)
	canyon.set_meta("no_blocking_collisions", true)
	canyon.set_meta("bank_roots", bank_roots)
	canyon.set_meta("flow_particle_count", TRACE_COUNT)
	canyon.set_meta("draw_batches", 4)
	return canyon

func animate(time: float, viewer: Vector3) -> void:
	# A viewer at either mouth must still see nearby cliffs, even when they are
	# far from the midpoint of the longer, winding canyon.
	var nearest_z: float = clampf(viewer.z,CENTER_Z-Ocean.CANYON_HALF_LENGTH,CENTER_Z+Ocean.CANYON_HALF_LENGTH)
	var nearest := Vector3(Ocean.canyon_center_x(nearest_z),clampf(viewer.y,-118.0,35.0),nearest_z)
	visible = viewer.distance_to(nearest) < 300.0
	if current_material != null:
		current_material.set_shader_parameter("flow_clock", time)

static func _batch(parent: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for index in range(batch.instance_count):
		batch.set_instance_transform(index, transforms[index])
		batch.set_instance_color(index, colors[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = batch
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = VIEW_DISTANCE
	visual.visibility_range_end_margin = 35.0
	parent.add_child(visual)

static func _bank_mesh(origin: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Copy the terrain's four-metre cells and diagonals exactly. Resampling a finer
	# bank grid produces crossing triangles and flickering against the real slope.
	var step: float = Ocean.TERRAIN_STEP
	var z_start: float = floor((CENTER_Z - Ocean.CANYON_HALF_LENGTH) / step) * step
	var z_end: float = ceil((CENTER_Z + Ocean.CANYON_HALF_LENGTH) / step) * step
	var x_min: float = INF
	var x_max: float = -INF
	for row in range(int((z_end-z_start)/step)+1):
		var center: float = Ocean.canyon_center_x(z_start+float(row)*step)
		x_min = minf(x_min,center-Ocean.CANYON_BANK_HALF_WIDTH-step)
		x_max = maxf(x_max,center+Ocean.CANYON_BANK_HALF_WIDTH+step)
	var x_start: float = floor(x_min/step)*step
	var columns: int = int(ceil((x_max-x_start)/step))
	for row in range(int((z_end-z_start)/step)):
		var z: float = z_start + float(row) * step
		for column in range(columns):
			var x: float = x_start + float(column) * step
			var across: float = absf(x + step * 0.5 - Ocean.canyon_center_x(z + step * 0.5))
			if across < Ocean.CANYON_FLOOR_HALF_WIDTH or across > Ocean.CANYON_BANK_HALF_WIDTH + 1.0:
				continue
			var a := Vector3(x, Ocean.terrain_vertex_height(x, z) + 0.045, z) - origin
			var b := Vector3(x + step, Ocean.terrain_vertex_height(x + step, z) + 0.045, z) - origin
			var c := Vector3(x, Ocean.terrain_vertex_height(x, z + step) + 0.045, z + step) - origin
			var d := Vector3(x + step, Ocean.terrain_vertex_height(x + step, z + step) + 0.045, z + step) - origin
			for point: Vector3 in [a, b, c, b, d, c]:
				var height: float = point.y + origin.y
				var band: float = fposmod(floor(height / 3.4), 3.0) / 2.0
				var color := Color("7b9087").lerp(Color("b3b6a1"), band * 0.65)
				surface.set_color(color.lerp(Color("bfb59a"),smoothstep(-2.0,7.0,height)*0.55))
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

func _build_current(origin: Vector3) -> void:
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Soft suspended matter and wisps, with no arrowheads or diagram-like symbols.
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:
		for segment in range(8):
			var u0: float = float(segment)/8.0
			var u1: float = float(segment+1)/8.0
			for uv: Vector2 in [Vector2(u0,0),Vector2(u0,1),Vector2(u1,1),Vector2(u0,0),Vector2(u1,1),Vector2(u1,0)]:
				shape.set_uv(uv)
				shape.add_vertex(axis*(uv.y*2.0-1.0)+Vector3(0,0,uv.x*2.0-1.0))
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = shape.commit()
	batch.instance_count = TRACE_COUNT
	for index in range(TRACE_COUNT):
		var row: int = int(index / 16)
		var lane: float = (float(index % 8) - 3.5) * 2.7+sin(float(index)*2.4)*.5
		var reach: float = Ocean.CANYON_HALF_LENGTH - TRACE_TRAVEL * 0.5 - 8.0
		var z: float = CENTER_Z - reach + float(row) * reach * 2.0 / float(TRACE_COUNT/16-1)
		var x: float = Ocean.canyon_center_x(z) + lane
		# Cover each ribbon's complete motion segment before choosing its height.
		# The floor rises at the mouths, so a fixed depth can pass into the bank.
		var highest_floor: float = -INF
		for sample in range(17):
			var sample_z: float = z-TRACE_TRAVEL*0.5+float(sample)*TRACE_TRAVEL/16.0
			highest_floor = maxf(highest_floor,Ocean.seabed_height(Ocean.canyon_center_x(sample_z)+lane,sample_z))
		var y: float = minf(-7.0,highest_floor + 10.0 + float(int(index / 8) % 2) * 9.0+sin(index*1.7)*2.0)
		batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(x,y,z) - origin))
		batch.set_instance_custom_data(index, Color(fposmod(float(index) * 0.618034, 1.0), (z - CENTER_Z + Ocean.CANYON_HALF_LENGTH) / LENGTH, float(index%5)/4.0, float(index % 7) / 7.0))
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float flow_clock = 0.0;
uniform float canyon_center_z = -230.0;
uniform float canyon_half_length = 225.0;
uniform float curve_amplitude = 26.0;
uniform float curve_frequency = 0.018;
uniform float trace_travel = 32.0;
uniform float flow_speed = 2.2;
varying float trace_alpha;
varying float particle_kind;
float center_offset(float z) {
    return curve_amplitude * sin((z-canyon_center_z)*curve_frequency);
}
float slope_at(float z) {
    return curve_amplitude * curve_frequency * cos((z-canyon_center_z)*curve_frequency);
}
float arc_metric(float z) {
    float slope = slope_at(z);
    return sqrt(1.0+slope*slope);
}
void vertex() {
    float phase = fract(flow_clock * flow_speed / trace_travel + INSTANCE_CUSTOM.r);
    float travel = (phase-0.5)*trace_travel;
    float base_z = canyon_center_z + (INSTANCE_CUSTOM.g*2.0-1.0)*canyon_half_length;
    float drift = travel/arc_metric(base_z);
    // Simpson's arc-length estimate keeps speed at 2.2 m/s around each bend.
    for (int iteration=0;iteration<3;iteration++) {
        float metric = (arc_metric(base_z)+4.0*arc_metric(base_z+drift*0.5)+arc_metric(base_z+drift))/6.0;
        drift = travel/metric;
    }
    float trace_z = base_z+drift;
    vec3 tangent = normalize(vec3(slope_at(trace_z),0.0,1.0));
    vec3 right = vec3(tangent.z,0.0,-tangent.x);
    vec3 point = VERTEX;
    particle_kind = INSTANCE_CUSTOM.b;
    float wisp = 1.0-step(0.1,particle_kind);
    float length_scale = mix(0.075+INSTANCE_CUSTOM.a*0.08,1.2+INSTANCE_CUSTOM.a*0.8,wisp);
    point.xy *= mix(0.065,0.10,wisp);
    point.z *= length_scale;
    point.x += wisp*sin(point.z*1.7+flow_clock*0.6+INSTANCE_CUSTOM.r*6.283)*0.11;
    point.y += sin(flow_clock*0.4+INSTANCE_CUSTOM.r*6.283)*0.15;
    VERTEX = right*point.x + vec3(0.0,point.y,0.0) + tangent*point.z;
    VERTEX += vec3(center_offset(trace_z)-center_offset(base_z),0.0,drift);
    trace_alpha = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.88, 1.0, phase));
}
void fragment() {
    float wisp = 1.0-step(0.1,particle_kind);
    float bubble = step(0.9,particle_kind);
    vec2 p = UV*2.0-1.0;
    float radius = length(p);
    float speck = 1.0-smoothstep(0.2,0.95,radius);
    float ring = (1.0-smoothstep(0.78,1.0,radius))*smoothstep(0.48,0.74,radius);
    float ribbon = pow(max(0.0,1.0-p.x*p.x),1.6)*pow(max(0.0,1.0-abs(p.y)),2.0);
    float softness = mix(mix(speck,ring,bubble),ribbon,wisp);
    ALBEDO = mix(vec3(0.60,0.73,0.70),vec3(0.57,0.78,0.81),bubble);
    EMISSION = ALBEDO * 0.12;
    ALPHA = trace_alpha * softness * mix(0.58,0.32,wisp);
}
"""
	current_material = ShaderMaterial.new()
	current_material.shader = shader
	current_material.set_shader_parameter("canyon_center_z",CENTER_Z)
	current_material.set_shader_parameter("canyon_half_length",Ocean.CANYON_HALF_LENGTH)
	current_material.set_shader_parameter("curve_amplitude",Ocean.CANYON_BEND_AMPLITUDE)
	current_material.set_shader_parameter("curve_frequency",Ocean.CANYON_BEND_FREQUENCY)
	current_material.set_shader_parameter("trace_travel",TRACE_TRAVEL)
	current_material.set_shader_parameter("flow_speed",Ocean.CANYON_CURRENT_SPEED)
	var visual := MultiMeshInstance3D.new()
	visual.name = "CurrentTraces"
	visual.multimesh = batch
	visual.material_override = current_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = VIEW_DISTANCE
	visual.visibility_range_end_margin = 35.0
	# Include the entire shader-deformed stream, both bends and all vertical tiers.
	var x_min: float = INF
	var x_max: float = -INF
	for sample in range(101):
		var sample_z: float = CENTER_Z-Ocean.CANYON_HALF_LENGTH+LENGTH*float(sample)/100.0
		var center: float = Ocean.canyon_center_x(sample_z)
		x_min = minf(x_min,center-Ocean.CANYON_FLOOR_HALF_WIDTH-3.0)
		x_max = maxf(x_max,center+Ocean.CANYON_FLOOR_HALF_WIDTH+3.0)
	visual.custom_aabb = AABB(Vector3(x_min,-122.0,CENTER_Z-Ocean.CANYON_HALF_LENGTH-3.0)-origin,Vector3(x_max-x_min,122.0,LENGTH+6.0))
	add_child(visual)
