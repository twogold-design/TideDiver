class_name TidalCanyonArt
extends Node3D
## Exposed canyon banks and current tracers; the shared seabed supplies all collision.
const Ocean = preload("res://scripts/ocean_config.gd")
const Coral = preload("res://scripts/coral_garden.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const CENTER_Z := -230.0
const LENGTH := 280.0
const TRACE_COUNT := 160
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
	for bank: float in [-1.0, 1.0]:
		for row in range(28):
			var z: float = CENTER_Z - 135.0 + float(row) * 10.0
			for tier in range(2):
				var x: float = Ocean.canyon_center_x(z) + bank * (23.0 + float(tier) * 16.0 + random.randf_range(-1.0, 1.0))
				var root := Vector3(x, Ocean.seabed_height(x, z), z) - origin
				var size := Vector3(random.randf_range(3.0, 5.2), random.randf_range(1.2, 3.0), random.randf_range(4.0, 6.2))
				rock_transforms.append(Transform3D(Basis(Vector3.UP, random.randf_range(-0.22, 0.22)).scaled(size), root + Vector3.UP * size.y * 0.2))
				rock_colors.append(Color("426777").lerp(Color("779096"), random.randf()))
				bank_roots.append(root)
			if row % 2 == 0:
				var x: float = Ocean.canyon_center_x(z) + bank * 34.0
				var root := Vector3(x, Ocean.seabed_height(x, z), z) - origin
				fan_transforms.append(Transform3D(Basis(Vector3.UP, random.randf_range(-PI, PI)).scaled(Vector3.ONE * random.randf_range(0.7, 1.0)), root))
				fan_colors.append(Color("bc9ac2").lerp(Color("cda788"), random.randf()))
				bank_roots.append(root)
	var strata := MeshInstance3D.new()
	strata.name = "LayeredBanks"
	strata.mesh = _bank_mesh(origin)
	strata.material_override = Geology.rock_material()
	strata.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strata.visibility_range_end = 290.0
	strata.visibility_range_end_margin = 20.0
	canyon.add_child(strata)
	var rock: ArrayMesh = Geology.rock_mesh(2)
	_batch(canyon, "RockShelves", rock, rock_transforms, rock_colors, _rock_material())
	_batch(canyon, "SparseSeaFans", Coral._coral_mesh(2), fan_transforms, fan_colors, _rock_material())
	canyon._build_current(origin)
	canyon.set_meta("world_center", Vector3(Ocean.canyon_center_x(CENTER_Z), Ocean.seabed_height(-210, CENTER_Z), CENTER_Z))
	canyon.set_meta("length", LENGTH)
	canyon.set_meta("flow_direction", Vector3.BACK)
	canyon.set_meta("channel_width", Ocean.CANYON_FLOOR_HALF_WIDTH * 2.0)
	canyon.set_meta("bank_span", Ocean.CANYON_BANK_HALF_WIDTH * 2.0)
	canyon.set_meta("no_blocking_collisions", true)
	canyon.set_meta("bank_roots", bank_roots)
	canyon.set_meta("flow_particle_count", TRACE_COUNT)
	canyon.set_meta("draw_batches", 4)
	return canyon

func animate(time: float, viewer: Vector3) -> void:
	var center: Vector3 = get_meta("world_center")
	visible = viewer.distance_to(center) < 310.0
	if current_material != null:
		current_material.set_shader_parameter("flow_clock", time)

static func _rock_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

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
	visual.visibility_range_end = 290.0
	visual.visibility_range_end_margin = 20.0
	parent.add_child(visual)

static func _bank_mesh(origin: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Copy the terrain's four-metre cells and diagonals exactly. Resampling a finer
	# bank grid produces crossing triangles and flickering against the real slope.
	var step: float = Ocean.TERRAIN_STEP
	var z_start: float = floor((CENTER_Z - LENGTH * 0.5) / step) * step
	var x_start: float = floor((Ocean.CANYON_CENTER.x - 54.0) / step) * step
	for row in range(71):
		var z: float = z_start + float(row) * step
		for column in range(28):
			var x: float = x_start + float(column) * step
			var across: float = absf(x + step * 0.5 - Ocean.canyon_center_x(z + step * 0.5))
			if across < 14.0 or across > Ocean.CANYON_BANK_HALF_WIDTH + 1.0:
				continue
			var a := Vector3(x, Ocean.terrain_vertex_height(x, z) + 0.045, z) - origin
			var b := Vector3(x + step, Ocean.terrain_vertex_height(x + step, z) + 0.045, z) - origin
			var c := Vector3(x, Ocean.terrain_vertex_height(x, z + step) + 0.045, z + step) - origin
			var d := Vector3(x + step, Ocean.terrain_vertex_height(x + step, z + step) + 0.045, z + step) - origin
			for point: Vector3 in [a, c, b, b, c, d]:
				var band: float = fposmod(floor((point.y + origin.y) / 3.4), 3.0) / 2.0
				surface.set_color(Color("78908e").lerp(Color("afb4a2"), band * 0.65))
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

func _build_current(origin: Vector3) -> void:
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Crossed ribbons remain readable from the bank, above, and inside the channel.
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:
		for vertex: Vector3 in [-axis * 0.055 + Vector3(0,0,-1.8), axis * 0.055 + Vector3(0,0,-1.8), axis * 0.055 + Vector3(0,0,0.65), -axis * 0.055 + Vector3(0,0,-1.8), axis * 0.055 + Vector3(0,0,0.65), -axis * 0.055 + Vector3(0,0,0.65), -axis * 0.24 + Vector3(0,0,0.42), Vector3(0,0,1.05), axis * 0.24 + Vector3(0,0,0.42)]:
			shape.add_vertex(vertex)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = shape.commit()
	batch.instance_count = TRACE_COUNT
	for index in range(TRACE_COUNT):
		var row: int = int(index / 8)
		var lane: float = (float(index % 4) - 1.5) * 5.6
		var z: float = CENTER_Z - 120.0 + float(row) * 240.0 / 19.0
		var x: float = Ocean.canyon_center_x(z) + lane
		var y: float = Ocean.seabed_height(x, z) + 10.0 + float(int(index / 4) % 2) * 9.0
		batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(x,y,z) - origin))
		batch.set_instance_custom_data(index, Color(fposmod(float(index) * 0.618034, 1.0), (z - CENTER_Z + 140.0) / 280.0, 0, float(index % 7) / 7.0))
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float flow_clock = 0.0;
varying float trace_alpha;
void vertex() {
    float rate = 2.2 + INSTANCE_CUSTOM.a * 0.5;
    float phase = fract(flow_clock * rate / 24.0 + INSTANCE_CUSTOM.r);
    float drift = phase * 24.0 - 12.0;
    float base_z = INSTANCE_CUSTOM.g * 280.0 - 140.0;
    VERTEX.z += drift;
    VERTEX.x += 5.0 * (sin((base_z + drift) * 0.045) - sin(base_z * 0.045));
    trace_alpha = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.88, 1.0, phase));
}
void fragment() {
    ALBEDO = vec3(0.42, 0.83, 0.87);
    EMISSION = ALBEDO * 0.28;
    ALPHA = trace_alpha * 0.62;
}
"""
	current_material = ShaderMaterial.new()
	current_material.shader = shader
	var visual := MultiMeshInstance3D.new()
	visual.name = "CurrentTraces"
	visual.multimesh = batch
	visual.material_override = current_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 285.0
	visual.custom_aabb = AABB(Vector3(Ocean.CANYON_CENTER.x-22,-120,CENTER_Z-150)-origin, Vector3(44,110,300))
	add_child(visual)
