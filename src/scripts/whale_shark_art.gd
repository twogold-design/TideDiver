extends RefCounted
## Original large whale shark, facing -Z. Shared meshes and one skin draw material.
const LENGTH := 17.65
const FIN_SPAN := 10.4
const BODY_SECTIONS := [
	Vector3(-6.75,1.35,.30), Vector3(-6.55,1.85,.50),
	Vector3(-6.0,2.15,.72), Vector3(-5.0,2.30,.92),
	Vector3(-3.6,2.25,1.10), Vector3(-2.0,2.05,1.15),
	Vector3(0.0,1.65,1.0), Vector3(2.0,1.15,.75),
	Vector3(4.0,.63,.48), Vector3(5.6,.27,.28), Vector3(6.5,.20,.22),
]
static var _meshes: Dictionary = {}
static var _skin_shader: Shader
static var _dark: StandardMaterial3D
static var _lip: StandardMaterial3D
static var _eye: StandardMaterial3D
static var _eye_mesh: SphereMesh

static func build() -> Node3D:
	_prepare_materials()
	var model := Node3D.new()
	model.name = "WhaleSharkModel"
	var skin := ShaderMaterial.new()
	skin.shader = _skin_shader
	model.set_meta("skin_material",skin)
	model.set_meta("length_m",LENGTH)
	model.set_meta("fin_span_m",FIN_SPAN)
	_visual(model,"BroadHeadAndBody",_body_mesh(),skin)
	_visual(model,"PectoralAndPelvicFins",_paired_fins_mesh(),skin)
	_visual(model,"DorsalFins",_dorsal_mesh(),skin)
	_visual(model,"CrescentTail",_tail_mesh(),skin)
	_visual(model,"FiveGillSlits",_gills_mesh(),_dark)
	_visual(model,"WideMouth",_mouth_mesh(false),_dark)
	_visual(model,"MouthRim",_mouth_mesh(true),_lip)
	for side: float in [-1.0,1.0]:
		var eye := _visual(model,"EyeLeft" if side < 0 else "EyeRight",_eye_mesh,_eye)
		eye.position = Vector3(side*1.95,.15,-6.14)
		eye.scale = Vector3(.13,.13,.15)
	animate(model,0.0)
	return model

static func animate(model: Node3D, time: float) -> void:
	# No wall clock/TIME: pausing or sketching freezes the entire swimming stroke.
	var skin: ShaderMaterial = model.get_meta("skin_material")
	skin.set_shader_parameter("swim_clock",time)

static func _prepare_materials() -> void:
	if _skin_shader != null:
		return
	_skin_shader = Shader.new()
	_skin_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float swim_clock = 0.0;
varying vec3 rest_position;
varying vec3 rest_normal;
void vertex() {
    rest_position = VERTEX;
    rest_normal = NORMAL;
    float rear = max(0.0, VERTEX.z + 1.4);
    // Increasing wave amplitude makes the massive forebody feel steady.
    float phase = swim_clock * 0.85 - VERTEX.z * 0.34;
    float bend = rear * rear * 0.010;
    VERTEX.x += sin(phase) * bend;
    float slope = cos(phase) * -0.34 * bend + sin(phase) * rear * 0.020;
    NORMAL = normalize(vec3(NORMAL.x, NORMAL.y, NORMAL.z - NORMAL.x * slope));
    VERTEX.y += sin(swim_clock * 0.55 + sign(VERTEX.x) * 0.12) * COLOR.a * 0.09;
}
void fragment() {
    float upper = smoothstep(-0.48, 0.08, rest_normal.y);
    vec3 belly = vec3(0.62,0.71,0.67);
    vec3 back = mix(vec3(0.19,0.33,0.38),vec3(0.12,0.23,0.28),clamp(rest_normal.y,0.0,1.0));
    vec3 base = mix(belly,back,upper);
    vec2 mapping = UV;
    if (rest_normal.z < -0.85) {
        mapping = vec2(rest_position.x,rest_position.y - 6.8);
    }
    vec2 grid = vec2(mapping.x * 2.55, mapping.y * 2.05);
    grid.x += mod(floor(grid.y),2.0) * 0.5;
    float variation = fract(sin(dot(floor(grid),vec2(127.1,311.7))) * 43758.5453);
    vec2 centered = fract(grid) - vec2(0.5) - vec2(variation-0.5,0.5-variation)*0.12;
    float radius = mix(0.14,0.18,variation);
    float spots = 1.0 - smoothstep(radius,radius+0.065,length(centered));
    float stripes = 1.0 - smoothstep(0.025,0.065,abs(fract(mapping.x * 1.275) - 0.5));
    float pattern = max(spots * mix(0.65,0.85,variation),stripes * 0.16) * upper;
    ALBEDO = mix(base,vec3(0.80,0.86,0.78),pattern);
    ROUGHNESS = 0.65;
    METALLIC = 0.0;
    SPECULAR = 0.32;
}
"""
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color("142c31")
	_dark.roughness = .8
	_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lip = StandardMaterial3D.new()
	_lip.albedo_color = Color("94aba3")
	_lip.roughness = .72
	_lip.cull_mode = BaseMaterial3D.CULL_DISABLED
	_eye = StandardMaterial3D.new()
	_eye.albedo_color = Color("101e22")
	_eye.roughness = .22
	_eye_mesh = SphereMesh.new()
	_eye_mesh.radius = 1.0
	_eye_mesh.height = 2.0
	_eye_mesh.radial_segments = 12
	_eye_mesh.rings = 6

static func _visual(parent: Node3D, label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.extra_cull_margin = 2.0
	parent.add_child(visual)
	return visual

static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

static func _vertex(surface: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, wing: float = 0.0) -> void:
	surface.set_normal(normal.normalized())
	surface.set_color(Color(1,1,1,wing))
	surface.set_uv(uv)
	surface.add_vertex(point)

static func _profile(z: float) -> Vector2:
	for index in range(BODY_SECTIONS.size()-1):
		var near: Vector3 = BODY_SECTIONS[index]
		var far: Vector3 = BODY_SECTIONS[index+1]
		if z <= far.x:
			var t := clampf((z-near.x)/(far.x-near.x),0.0,1.0)
			var previous: Vector3 = BODY_SECTIONS[maxi(index-1,0)]
			var after: Vector3 = BODY_SECTIONS[mini(index+2,BODY_SECTIONS.size()-1)]
			return Vector2(near.y,near.z).cubic_interpolate(Vector2(far.y,far.z),Vector2(previous.y,previous.z),Vector2(after.y,after.z),t)
	return Vector2(.20,.22)

static func _body_vertex(surface: SurfaceTool, z: float, angle: float) -> void:
	var shape: Vector2 = _profile(z)
	var point := Vector3(cos(angle)*shape.x,sin(angle)*shape.y,z)
	var before: Vector2 = _profile(z-.015)
	var after: Vector2 = _profile(z+.015)
	var slope := (after-before)/.03
	var normal := Vector3(cos(angle)/shape.x,sin(angle)/shape.y,-cos(angle)*cos(angle)*slope.x/shape.x-sin(angle)*sin(angle)*slope.y/shape.y)
	_vertex(surface,point,normal,Vector2(angle*1.55,z))

static func _body_mesh() -> ArrayMesh:
	if _meshes.has("body"):
		return _meshes.body
	var surface := _surface()
	const RINGS := 56
	const SIDES := 40
	for row in range(RINGS):
		var z0 := lerpf(-6.75,6.5,float(row)/RINGS)
		var z1 := lerpf(-6.75,6.5,float(row+1)/RINGS)
		for side in range(SIDES):
			var a := float(side)*TAU/SIDES
			var b := float(side+1)*TAU/SIDES
			_body_vertex(surface,z0,a)
			_body_vertex(surface,z1,a)
			_body_vertex(surface,z0,b)
			_body_vertex(surface,z0,b)
			_body_vertex(surface,z1,a)
			_body_vertex(surface,z1,b)
	# The terminal muzzle is broad and shallow instead of a pointed shark nose.
	for side in range(SIDES):
		var a := float(side)*TAU/SIDES
		var b := float(side+1)*TAU/SIDES
		_vertex(surface,Vector3(0,0,-6.82),Vector3.FORWARD,Vector2(0,-6.82))
		_vertex(surface,Vector3(cos(a)*1.35,sin(a)*.30,-6.75),Vector3.FORWARD,Vector2(a*1.55,-6.75))
		_vertex(surface,Vector3(cos(b)*1.35,sin(b)*.30,-6.75),Vector3.FORWARD,Vector2(b*1.55,-6.75))
	surface.index()
	_meshes.body = surface.commit()
	return _meshes.body

static func _fin(surface: SurfaceTool, outline: Array, thickness_axis: Vector3, thickness: float, wing: bool = false) -> void:
	var center := Vector3.ZERO
	for point: Vector3 in outline:
		center += point
	center /= outline.size()
	for side: float in [-1.0,1.0]:
		var crown: Vector3 = center + thickness_axis*thickness*side
		for index in range(outline.size()):
			var a: Vector3 = outline[index]
			var b: Vector3 = outline[(index+1)%outline.size()]
			var normal: Vector3 = (a-crown).cross(b-crown).normalized()
			if normal.dot(thickness_axis)*side < 0:
				normal = -normal
			for point: Vector3 in [crown,a,b]:
				var uv := Vector2(point.x,point.z) if absf(thickness_axis.y) > .5 else Vector2(point.y,point.z)
				_vertex(surface,point,normal,uv,maxf(0,absf(point.x)-2.0) if wing else 0.0)

static func _paired_fins_mesh() -> ArrayMesh:
	if _meshes.has("paired_fins"):
		return _meshes.paired_fins
	var surface := _surface()
	for side: float in [-1.0,1.0]:
		_fin(surface,[Vector3(side*1.9,-.38,-3.35),Vector3(side*2.8,-.58,-2.9),Vector3(side*4.0,-.88,-1.7),Vector3(side*5.2,-1.18,.6),Vector3(side*4.6,-1.0,.43),Vector3(side*3.5,-.72,-.05),Vector3(side*1.8,-.42,-.65)],Vector3.UP,.18,true)
		_fin(surface,[Vector3(side*.93,-.36,2.0),Vector3(side*1.4,-.5,2.45),Vector3(side*2.0,-.65,3.9),Vector3(side*.9,-.4,3.25)],Vector3.UP,.11)
	surface.index()
	_meshes.paired_fins = surface.commit()
	return _meshes.paired_fins

static func _dorsal_mesh() -> ArrayMesh:
	if _meshes.has("dorsal"):
		return _meshes.dorsal
	var surface := _surface()
	_fin(surface,[Vector3(0,.95,-1.15),Vector3(0,1.65,-.8),Vector3(0,2.85,.55),Vector3(0,3.12,1.05),Vector3(0,2.25,1.1),Vector3(0,.7,2.0)],Vector3.RIGHT,.19)
	_fin(surface,[Vector3(0,.47,3.4),Vector3(0,1.22,4.05),Vector3(0,.72,4.27),Vector3(0,.3,4.85)],Vector3.RIGHT,.10)
	_fin(surface,[Vector3(0,-.45,3.3),Vector3(0,-1.05,4.0),Vector3(0,-.29,4.8)],Vector3.RIGHT,.08)
	surface.index()
	_meshes.dorsal = surface.commit()
	return _meshes.dorsal

static func _tail_mesh() -> ArrayMesh:
	if _meshes.has("tail"):
		return _meshes.tail
	var surface := _surface()
	# Separate upper/lower lobes keep the concave trailing edge open.
	_fin(surface,[Vector3(0,.18,6.0),Vector3(0,.78,7.0),Vector3(0,1.95,8.35),Vector3(0,2.89,9.8),Vector3(0,3.22,10.83),Vector3(0,2.59,10.1),Vector3(0,1.69,9.3),Vector3(0,.56,8.35),Vector3(0,-.05,7.8)],Vector3.RIGHT,.17)
	_fin(surface,[Vector3(0,.08,6.0),Vector3(0,-.53,6.9),Vector3(0,-1.58,8.15),Vector3(0,-2.44,9.4),Vector3(0,-2.7,10.1),Vector3(0,-1.99,9.5),Vector3(0,-.98,8.55),Vector3(0,.08,7.8)],Vector3.RIGHT,.15)
	surface.index()
	_meshes.tail = surface.commit()
	return _meshes.tail

static func _gills_mesh() -> ArrayMesh:
	if _meshes.has("gills"):
		return _meshes.gills
	var surface := _surface()
	for side: float in [-1.0,1.0]:
		for slit in range(5):
			var z: float = -4.7 + slit*.34
			for segment in range(9):
				var a: float = lerpf(-.58,.63,float(segment)/9.0)
				var b: float = lerpf(-.58,.63,float(segment+1)/9.0)
				var shape: Vector2 = _profile(z)
				var p := Vector3(side*(cos(a)*shape.x+.022),sin(a)*shape.y,z+.09*sin(a))
				var q := Vector3(side*(cos(b)*shape.x+.022),sin(b)*shape.y,z+.09*sin(b))
				for point: Vector3 in [p,q,p+Vector3(0,0,.045),q,q+Vector3(0,0,.045),p+Vector3(0,0,.045)]:
					_vertex(surface,point,Vector3(side,0,0),Vector2.ZERO)
	surface.index()
	_meshes.gills = surface.commit()
	return _meshes.gills

static func _mouth_point(angle: float, expanded: float = 0.0) -> Vector3:
	var x := cos(angle)*(1.38+expanded)
	return Vector3(x,-.13+sin(angle)*(.115+expanded*.35),-6.84+pow(absf(x)/1.5,3.0)*.15)

static func _mouth_mesh(rim: bool) -> ArrayMesh:
	var key := "rim" if rim else "mouth"
	if _meshes.has(key):
		return _meshes[key]
	var surface := _surface()
	for segment in range(48):
		var a := float(segment)*TAU/48.0
		var b := float(segment+1)*TAU/48.0
		var points: Array
		if rim:
			points = [_mouth_point(a),_mouth_point(b),_mouth_point(a,.06),_mouth_point(b),_mouth_point(b,.06),_mouth_point(a,.06)]
		else:
			points = [Vector3(0,-.13,-6.855),_mouth_point(a),_mouth_point(b)]
		for point: Vector3 in points:
			_vertex(surface,point,Vector3.FORWARD,Vector2.ZERO)
	surface.index()
	_meshes[key] = surface.commit()
	return _meshes[key]
