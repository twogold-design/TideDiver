extends Node3D
## Short exhalations from the regulator; pooled translucent bubbles rise in world space.
const MAX_BUBBLES := 64
const REGULATOR := Vector3(0.10,-0.12,-1.24)
var particles: Array[Dictionary] = []
var batch: MultiMesh
var visual: MultiMeshInstance3D
var ignored_bodies: Array[RID] = []
var breath_timer := 0.9
var burst_left := 0
var bubble_timer := 0.0
var emitted_count := 0
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	name = "DiverBreathBubbles"
	_random.seed = 93716
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode blend_mix, cull_back, shadows_disabled;
varying float bubble_alpha;
void vertex() {
    bubble_alpha = COLOR.a;
}
void fragment() {
    float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.4);
    float glint = pow(max(dot(normalize(NORMAL), normalize(vec3(-0.4,0.7,0.55))), 0.0), 24.0);
    ALBEDO = mix(vec3(0.30,0.57,0.62), vec3(0.80,0.94,0.94), rim);
    ROUGHNESS = 0.10;
    SPECULAR = 0.85;
    ALPHA = (0.035 + rim * 0.50 + glint * 0.35) * bubble_alpha;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = sphere
	batch.instance_count = MAX_BUBBLES
	batch.visible_instance_count = 0
	visual = MultiMeshInstance3D.new()
	visual.name = "BreathTrail"
	visual.multimesh = batch
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

func reset() -> void:
	particles.clear()
	breath_timer = 0.9
	burst_left = 0
	bubble_timer = 0.0
	emitted_count = 0
	if batch != null:
		batch.visible_instance_count = 0

func advance(delta: float, rig: Transform3D, emitting: bool, effort: float, current: Vector3) -> void:
	if delta <= 0.0:
		return
	var mouth: Vector3 = rig * REGULATOR
	if emitting and mouth.y < -0.4:
		breath_timer -= delta
		if breath_timer <= 0.0:
			burst_left = 9 + int(clampf(effort,0.0,1.0)*4.0)
			bubble_timer = 0.0
			breath_timer = lerpf(4.1,2.6,clampf(effort,0.0,1.0))+_random.randf_range(-0.3,0.3)
		bubble_timer -= delta
		# Limit catch-up after a stalled browser frame to one small breath.
		while burst_left > 0 and bubble_timer <= 0.0:
			_spawn(mouth,rig.basis,current)
			burst_left -= 1
			bubble_timer += 0.065
	else:
		burst_left = 0
	for index in range(particles.size()-1,-1,-1):
		var bubble: Dictionary = particles[index]
		bubble.age += delta
		if bubble.age >= bubble.life:
			particles.remove_at(index)
			continue
		var old: Vector3 = bubble.position
		var rise: float = minf(1.65,0.65+float(bubble.age)*0.32)
		var wobble := Vector3(sin(bubble.age*3.1+bubble.phase),0,cos(bubble.age*2.6+bubble.phase))*0.10
		bubble.position += (bubble.drift+wobble+Vector3.UP*rise)*delta
		if bubble.position.y >= -0.15:
			particles.remove_at(index)
			continue
		var query := PhysicsRayQueryParameters3D.create(old,bubble.position,1,ignored_bodies)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			particles.remove_at(index)
	_upload()

func _spawn(mouth: Vector3, basis: Basis, current: Vector3) -> void:
	if particles.size() >= MAX_BUBBLES:
		return
	var spread := Vector3(_random.randf_range(-0.13,0.13),_random.randf_range(-0.025,0.035),0)
	particles.append({
		"position":mouth+basis*spread,
		"drift":current*0.20+basis*Vector3(_random.randf_range(-0.13,0.13),0,-0.10),
		"age":0.0,"life":_random.randf_range(3.4,4.6),
		"radius":_random.randf_range(0.045,0.105),"phase":_random.randf_range(0.0,TAU)
	})
	emitted_count += 1

func _upload() -> void:
	batch.visible_instance_count = particles.size()
	if particles.is_empty():
		return
	var bounds := AABB(particles[0].position,Vector3.ZERO)
	for index in range(particles.size()):
		var bubble: Dictionary = particles[index]
		var age: float = bubble.age
		var size: float = bubble.radius*(1.0+minf(age,3.5)*0.12)
		var shape := Vector3(1.0+sin(age*5.0+bubble.phase)*0.07,0.92,1.0)*size
		batch.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(shape),bubble.position))
		var fade: float = smoothstep(0.0,0.12,age)*(1.0-smoothstep(bubble.life-0.8,bubble.life,age))
		batch.set_instance_color(index,Color(1,1,1,fade))
		bounds = bounds.expand(bubble.position)
	visual.custom_aabb = bounds.grow(0.25)
