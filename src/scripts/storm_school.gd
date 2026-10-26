extends Node3D
## A localized silver jackfish vortex, drawn in one batch with a shared mesh.
const CENTER := Vector3(-45,-20,292)
const FISH_COUNT := 420
const RADIUS := 18.0
var school: MultiMeshInstance3D

func _ready() -> void:
	name = "JackfishStorm"
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = _fish_mesh()
	batch.instance_count = FISH_COUNT
	for i in range(FISH_COUNT):
		var height: float = -8.0 + float(i % 14) * 1.2 + sin(float(i)*1.73)*0.36
		var angle: float = float(i) * 2.399963 + height * 0.13
		var radius: float = 11.5 + 2.4 * sin(height * 0.21) + fposmod(float(i)*0.73,3.1)
		var point := Vector3(cos(angle)*radius,height,sin(angle)*radius)
		var tangent := Vector3(-sin(angle),0,cos(angle))
		var basis := Basis.looking_at(tangent,Vector3.UP)
		basis = basis.scaled(Vector3.ONE*(0.72 + float(i%5)*0.06))
		batch.set_instance_transform(i,Transform3D(basis,point))
		batch.set_instance_color(i,Color("bfdae0").lerp(Color("e7f2eb"),float(i%7)/7.0))
		batch.set_instance_custom_data(i,Color(fposmod(float(i)*0.618,1.0),0,0,1))
	school = MultiMeshInstance3D.new()
	school.name = "SilverVortex"
	school.multimesh = batch
	school.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	school.visibility_range_end = 160
	school.custom_aabb = AABB(Vector3(-20,-11,-20),Vector3(40,23,40))
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float swim_clock = 0.0;
varying vec4 fish_color;
void vertex() {
    float tail = smoothstep(0.35, 1.35, VERTEX.z);
    VERTEX.x += sin(swim_clock * 7.0 + INSTANCE_CUSTOM.r * 6.283) * tail * 0.10;
    fish_color = COLOR;
}
void fragment() {
    ALBEDO = fish_color.rgb;
    METALLIC = 0.38;
    ROUGHNESS = 0.36;
}
"""

	material.shader = shader
	school.material_override = material
	add_child(school)
	set_meta("fish_count",FISH_COUNT)
	set_meta("feature_name","杰克风暴")

func animate(time: float, viewer: Vector3) -> void:
	visible = viewer.distance_to(position) < 180.0
	rotation.y = time * 0.24
	if school != null:
		(school.material_override as ShaderMaterial).set_shader_parameter("swim_clock",time)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	for point: Vector3 in [a,b,c]:
		surface.add_vertex(point)

static func _fish_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A deep silver body and forked tail distinguish the jacks from the reef fish.
	for ring in range(6):
		var a: float = -PI/2 + float(ring)*PI/6
		var b: float = -PI/2 + float(ring+1)*PI/6
		for segment in range(10):
			var c: float = float(segment)*TAU/10
			var d: float = float(segment+1)*TAU/10
			var p := Vector3(sin(c)*cos(a)*0.21,sin(a)*0.35,cos(c)*cos(a)*0.78)
			var q := Vector3(sin(d)*cos(a)*0.21,sin(a)*0.35,cos(d)*cos(a)*0.78)
			var r := Vector3(sin(c)*cos(b)*0.21,sin(b)*0.35,cos(c)*cos(b)*0.78)
			var t := Vector3(sin(d)*cos(b)*0.21,sin(b)*0.35,cos(d)*cos(b)*0.78)
			var color := Color("789ba8") if ring >= 4 else Color("e3ece5")
			_triangle(surface,p,q,r,color)
			_triangle(surface,q,t,r,color)
	var fin := Color("7293a0")
	_triangle(surface,Vector3(0,0,0.63),Vector3(0,0.58,1.28),Vector3(0,0.1,1.02),fin)
	_triangle(surface,Vector3(0,0,0.63),Vector3(0,-0.58,1.28),Vector3(0,-0.1,1.02),fin)
	_triangle(surface,Vector3(0,0.25,-0.26),Vector3(0,0.61,0.16),Vector3(0,0.21,0.51),fin)
	for side: float in [-1.0,1.0]:
		_triangle(surface,Vector3(side*0.2,-0.06,-0.3),Vector3(side*0.57,-0.19,0.28),Vector3(side*0.19,-0.1,0.2),fin)
		_triangle(surface,Vector3(side*0.2,0.09,-0.53),Vector3(side*0.21,0.17,-0.47),Vector3(side*0.21,0.04,-0.44),Color("183947"))
	surface.generate_normals()
	return surface.commit()
