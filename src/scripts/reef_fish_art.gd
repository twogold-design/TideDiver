extends RefCounted
## Original small reef fish. Shared meshes face -Z; markings follow the body surface.
const Shapes = preload("res://scripts/marine_life_art.gd")
static var _meshes: Dictionary = {}
static var _shader: Shader

static func material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float school_clock = 0.0;
varying vec3 pigment;
void vertex() {
    float tail = smoothstep(0.02, 0.40, VERTEX.z);
    VERTEX.x += sin(school_clock * (6.0 + INSTANCE_CUSTOM.g * 2.0) + INSTANCE_CUSTOM.r * 6.283185) * tail * 0.035;
    pigment = COLOR.rgb;
}
void fragment() {
    ALBEDO = pigment;
    ROUGHNESS = 0.72;
    SPECULAR = 0.22;
    EMISSION = pigment * 0.055;
}
"""
	var result := ShaderMaterial.new()
	result.shader = _shader
	return result

static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wide: float = 0.10
	var tall: float = 0.15
	if kind in ["butterfly","tang","banner"]:
		wide = 0.075
		tall = 0.23
	elif kind == "squirrel":
		tall = 0.13
	# Many short rings let cream bands and dark outlines wrap around rounded bodies.
	for ring in range(32):
		var z0: float = lerpf(-0.31,0.25,float(ring)/32.0)
		var z1: float = lerpf(-0.31,0.25,float(ring+1)/32.0)
		for side in range(16):
			var a: float = float(side)*TAU/16.0
			var b: float = float(side+1)*TAU/16.0
			var tint: Color = _pigment(kind,(z0+z1)*0.5,(a+b)*0.5)
			Shapes._quad(surface,_body(z0,a,wide,tall),_body(z0,b,wide,tall),_body(z1,a,wide,tall),_body(z1,b,wide,tall),tint)
	var fin: Color = _pigment(kind,0.10,0)
	if kind in ["tang","snapper","banner"]:
		fin = Color("e9be45")
	var tail_height: float = 0.14 if kind == "clown" else 0.19
	Shapes._quad(surface,Vector3(0,.025,.23),Vector3(0,-.025,.23),Vector3(0,tail_height,.43),Vector3(0,-tail_height,.43),Color("254550"))
	Shapes._quad(surface,Vector3(.001,.018,.24),Vector3(.001,-.018,.24),Vector3(.001,tail_height*.82,.414),Vector3(.001,-tail_height*.82,.414),fin)
	Shapes._triangle(surface,Vector3(0,tall*.70,-.20),Vector3(0,tall+0.075,.02),Vector3(0,tall*.40,.22),Color("263c48"))
	Shapes._triangle(surface,Vector3(.001,tall*.76,-.18),Vector3(.001,tall+0.052,.03),Vector3(.001,tall*.48,.20),fin)
	Shapes._triangle(surface,Vector3(0,-tall*.75,-.12),Vector3(0,-tall-0.055,.14),Vector3(0,-tall*.35,.23),fin)
	if kind == "banner":
		Shapes._triangle(surface,Vector3(0,.21,-.17),Vector3(0,.43,.18),Vector3(0,.26,.05),Color("e1daba"))
	for side: float in [-1.0,1.0]:
		Shapes._triangle(surface,Vector3(side*wide,-.01,-.12),Vector3(side*(wide+.13),-.07,.07),Vector3(side*wide,-.04,.10),fin.lightened(.12))
		var eye := Vector3(side*wide*.79,tall*.24,-.225)
		var radius: float = .035 if kind == "squirrel" else .023
		Shapes._oval(surface,eye,Vector3(.012,radius,radius),Color("d5be79"),8,4)
		Shapes._oval(surface,eye+Vector3(side*.009,0,-.003),Vector3(.008,radius*.72,radius*.72),Color("102c38"),8,4)
		Shapes._oval(surface,eye+Vector3(side*.016,radius*.30,-radius*.25),Vector3(.004,.005,.005),Color("c5dcd8"),6,3)
	surface.generate_normals()
	_meshes[kind] = surface.commit()
	return _meshes[kind]

static func _body(z: float, angle: float, width: float, height: float) -> Vector3:
	var profile: float = sqrt(maxf(0.005,1.0-pow((z+.045)/.29,2.0)))
	return Vector3(cos(angle)*width*profile,sin(angle)*height*profile,z)

static func _pigment(kind: String, z: float, angle: float) -> Color:
	var color := Color("55c6c9")
	match kind:
		"clown":
			color = Color("f18a32")
			var band: float = minf(absf(z+.22),minf(absf(z+.015),absf(z-.18)))
			if band < .040:
				color = Color("283a3e")
			if band < .026:
				color = Color("e5dfbd")
		"tang":
			color = Color("377dcc")
			if sin(angle) > .3 or (absf(sin(angle)) < .25 and z > -.12):
				color = Color("203653")
		"butterfly":
			color = Color("e7c956")
			if absf(z+.22) < .035 or absf(z-.11) < .035:
				color = Color("3e474c")
			elif sin(angle*7.0+z*28.0) > .82:
				color = Color("bd923c")
		"anthias":
			color = Color("ec9e58").lerp(Color("c06fa4"),clampf((sin(angle)+.25)*.65,0,1))
		"squirrel":
			color = Color("c85e48")
			if absf(sin(angle*5.0)) < .24:
				color = Color("e7bca2")
		"snapper":
			color = Color("8faeb9")
			if absf(sin(angle*4.0)) < .32:
				color = Color("dfbd57")
		"banner":
			color = Color("dcd9b9")
			if absf(z+.14) < .07 or absf(z-.12) < .065:
				color = Color("293e4a")
	return color.darkened(maxf(0,-sin(angle))*.10)

static func anemone_mesh() -> ArrayMesh:
	if _meshes.has("anemone"):
		return _meshes.anemone
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	Shapes._oval(surface,Vector3(0,.10,0),Vector3(.65,.18,.59),Color("99719c"),16,5)
	for i in range(56):
		var angle: float = float(i)*2.39996
		var reach: float = sqrt(float(i)/56.0)*.64
		var base := Vector3(cos(angle)*reach,.15,sin(angle)*reach)
		var tip: Vector3 = base+Vector3(cos(angle+.4)*.15,.33+.16*sin(i*1.7),sin(angle+.4)*.15)
		Shapes._curve(surface,PackedVector3Array([base,base.lerp(tip,.5)+Vector3(.04,0,0),tip]),.033,.022,Color("ad87ae"))
		Shapes._oval(surface,tip,Vector3.ONE*.047,Color("d4b6bb"),6,3)
	surface.generate_normals()
	_meshes.anemone = surface.commit()
	return _meshes.anemone
