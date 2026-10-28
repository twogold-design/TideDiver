extends RefCounted
## Shared original silhouettes, facing -Z. Vertex alpha stores appendage motion weight.
const FORMS := ["ShoreCrab", "SeaUrchin", "SeaCucumber", "CleanerShrimp", "Seahorse", "Cuttlefish", "GreenTurtle"]
static var _meshes: Dictionary = {}
static var _shader: Shader

static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"ShoreCrab": _crab(surface)
		"SeaUrchin": _urchin(surface)
		"SeaCucumber": _cucumber(surface)
		"CleanerShrimp": _shrimp(surface)
		"Seahorse": _seahorse(surface)
		"Cuttlefish": _cuttlefish(surface)
		"GreenTurtle": _turtle(surface)
		_:
			push_error("Unknown marine organism: " + kind)
			return ArrayMesh.new()
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	_meshes[kind] = result
	return result

static func material(kind: String) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float life_clock = 0.0;
uniform int organism = 0;
varying vec3 skin;
void vertex() {
    float phase = life_clock + INSTANCE_CUSTOM.r * 6.283185;
    float part = COLOR.a;
    if (organism == 0) {
        VERTEX.y += sin(phase * 3.2 + VERTEX.z * 12.0) * part * 0.035;
        VERTEX.x += sin(phase * 2.0 + VERTEX.z * 9.0) * part * 0.018;
    } else if (organism == 2) {
        VERTEX.y += sin(phase * 0.9 + VERTEX.z * 4.0) * part * 0.012;
    } else if (organism == 3) {
        VERTEX.y += sin(phase * 6.0 + VERTEX.z * 9.0) * part * 0.016;
    } else if (organism == 4) {
        VERTEX.x += sin(phase * 9.0 + VERTEX.y * 8.0) * part * 0.025;
    } else if (organism == 5) {
        VERTEX.y += sin(phase * 4.8 + VERTEX.z * 12.0) * part * 0.065;
    } else if (organism == 6) {
        VERTEX.y += sin(phase * 1.8) * part * 0.24;
        VERTEX.z += cos(phase * 1.8) * part * 0.045;
    }
    skin = COLOR.rgb;
}
void fragment() {
    ALBEDO = skin;
    ROUGHNESS = 0.82;
    SPECULAR = 0.14;
}
"""
	var result := ShaderMaterial.new()
	result.shader = _shader
	result.set_shader_parameter("organism", FORMS.find(kind))
	result.set_shader_parameter("life_clock", 0.0)
	return result

static func _crab(s: SurfaceTool) -> void:
	var shell := Color("b86c49")
	_oval(s, Vector3(0,0.25,0), Vector3(0.44,0.20,0.31), shell, 12, 6)
	# A serrated rim, inset carapace grooves and jointed lateral legs.
	for side: float in [-1.0, 1.0]:
		for leg in range(4):
			var z: float = -0.20 + leg * 0.14
			var hip := Vector3(side*0.32,0.21,z)
			var knee := Vector3(side*(0.64+0.06*sin(leg)),0.15,z+0.10)
			var tip := Vector3(side*(0.79-0.04*leg),0.025,z+0.28)
			_tube(s, hip, knee, 0.040, 0.026, shell.darkened(0.08), 5, 0.75)
			_tube(s, knee, tip, 0.028, 0.008, shell.lightened(0.15), 5, 1.0)
			_cone(s, Vector3(side*0.39,0.25,z), Vector3(side*0.48,0.27,z-0.03), 0.035, shell)
		var elbow := Vector3(side*0.50,0.19,-0.36)
		var palm := Vector3(side*0.58,0.22,-0.62)
		_tube(s, Vector3(side*0.28,0.21,-0.20), elbow, 0.07, 0.055, shell, 6, 0.35)
		_tube(s, elbow, palm, 0.055, 0.08, shell, 6, 0.60)
		_oval(s, palm, Vector3(0.105,0.09,0.14), shell.lightened(0.18), 8, 4, 0.6)
		_tube(s, palm+Vector3(-side*0.04,0,-0.07), palm+Vector3(-side*0.10,0,-0.24), 0.045, 0.008, Color("dfbc92"), 5, 0.7)
		_tube(s, palm+Vector3(side*0.05,0,-0.04), palm+Vector3(side*0.12,0,-0.18), 0.035, 0.012, shell, 5, 1.0)
		_tube(s, palm+Vector3(side*0.12,0,-0.18), palm+Vector3(-side*0.03,0,-0.24), 0.025, 0.007, Color("dfbc92"), 5, 1.0)
		_tube(s, Vector3(side*0.16,0.33,-0.22), Vector3(side*0.19,0.45,-0.32), 0.018, 0.014, shell)
		_oval(s, Vector3(side*0.19,0.45,-0.32), Vector3.ONE*0.032, Color("183337"), 6, 4)
		_tube(s, Vector3(side*0.09,0.40,-0.02), Vector3(side*0.26,0.34,0.13), 0.008, 0.006, shell.darkened(0.28), 4)

static func _urchin(s: SurfaceTool) -> void:
	_oval(s, Vector3(0,0.22,0), Vector3(0.29,0.23,0.29), Color("554468"), 12, 6)
	for ring in range(4):
		var elevation: float = 0.13 + ring*0.35
		for index in range(13):
			var angle: float = float(index)*TAU/13.0 + ring*0.49
			var normal := Vector3(cos(angle)*cos(elevation),sin(elevation),sin(angle)*cos(elevation))
			var base: Vector3 = Vector3(0,0.22,0)+normal*0.24
			var length: float = 0.28+0.16*fposmod(float(index)*0.618+ring*0.31,1.0)
			_cone(s, base, base+normal*length, 0.014, Color("776186").lerp(Color("c0a3bd"),float(ring)/4.0))
	# Five pale petal-shaped ambulacral bands identify the living test beneath the spines.
	for petal in range(5):
		var angle: float = float(petal)*TAU/5.0
		for dot in range(3):
			var point := Vector3(cos(angle)*dot*0.065,0.445-dot*0.013,sin(angle)*dot*0.065)
			_oval(s, point, Vector3.ONE*0.014, Color("c4b29d"), 5, 3)

static func _cucumber(s: SurfaceTool) -> void:
	var path := PackedVector3Array()
	var sizes := PackedVector2Array()
	for index in range(13):
		var u: float = float(index)/12.0
		path.append(Vector3(sin(u*PI)*0.10,0.19,lerpf(-0.74,0.74,u)))
		var radius: float = 0.065+0.155*pow(sin(u*PI),0.55)
		sizes.append(Vector2(radius,radius*0.78))
	_swept(s,path,sizes,Color("827548"),10,0.3)
	for row in range(9):
		var z: float = -0.58+row*0.145
		for side: float in [-1.0,1.0]:
			for elevation in range(3):
				var point := Vector3(side*(0.12+elevation*0.025),0.19+elevation*0.042,z)
				_cone(s,point,point+Vector3(side*0.022,0.055,0.008),0.027,Color("c0a875"))
			_tube(s,Vector3(side*0.10,0.09,z),Vector3(side*0.18,0.025,z),0.016,0.010,Color("a49469"),4)
	for arm in range(7):
		var angle: float = float(arm)*TAU/7.0
		var end := Vector3(cos(angle)*0.10,0.20+sin(angle)*0.09,-0.87)
		_tube(s,Vector3(0,0.19,-0.72),end,0.014,0.006,Color("bcae8a"),4,0.7)

static func _shrimp(s: SurfaceTool) -> void:
	var path := PackedVector3Array([Vector3(0,0.16,-0.30),Vector3(0,0.27,-0.12),Vector3(0,0.28,0.06),Vector3(0,0.22,0.24),Vector3(0,0.12,0.38)])
	var sizes := PackedVector2Array([Vector2(.07,.09),Vector2(.105,.12),Vector2(.09,.095),Vector2(.065,.07),Vector2(.025,.035)])
	_swept(s,path,sizes,Color("d77f64"),8,0.15)
	for ring in range(4):
		_oval(s,path[ring]+Vector3(0,0.018,0.01),Vector3(0.104-ring*.018,0.10-ring*.015,0.035),Color("f0d9bb"),8,4,0.3)
	for side: float in [-1.0,1.0]:
		for index in range(5):
			var hip := Vector3(side*.07,.18,-.22+index*.095)
			var knee := hip+Vector3(side*.10,-.06,-.03)
			_tube(s,hip,knee,.010,.007,Color("e8c5a0"),4,1.0)
			_tube(s,knee,knee+Vector3(side*.035,-.08,.07),.007,.003,Color("e8c5a0"),4,1.0)
		_oval(s,Vector3(side*.085,.29,-.22),Vector3.ONE*.027,Color("172f32"),6,4)
		var antenna := PackedVector3Array([Vector3(side*.04,.28,-.29),Vector3(side*.14,.34,-.51),Vector3(side*.29,.31,-.80),Vector3(side*.43,.26,-1.05)])
		_curve(s,antenna,.008,.002,Color("f3e7c9"),1.0)
		_leaf(s,Vector3(0,.10,.33),Vector3(side*.18,.08,.52),Vector3(side*.08,.10,.40),Color("ecbaa0"),.7)
	_tube(s,Vector3(0,.29,-.26),Vector3(0,.32,-.52),.020,.002,Color("e8cbb0"),4,.2)

static func _seahorse(s: SurfaceTool) -> void:
	var path := PackedVector3Array([Vector3(0,.32,.15),Vector3(0,.48,.10),Vector3(0,.70,.07),Vector3(0,.91,.10),Vector3(0,1.07,.015),Vector3(0,1.08,-.15)])
	var sizes := PackedVector2Array([Vector2(.045,.055),Vector2(.085,.11),Vector2(.13,.15),Vector2(.08,.09),Vector2(.07,.08),Vector2(.085,.09)])
	_swept(s,path,sizes,Color("ccaa60"),9)
	_oval(s,Vector3(0,1.10,-.15),Vector3(.09,.10,.13),Color("d0b16e"),9,5)
	_tube(s,Vector3(0,1.07,-.20),Vector3(0,1.00,-.43),.053,.025,Color("ddc387"),7)
	for side: float in [-1.0,1.0]:
		_oval(s,Vector3(side*.078,1.13,-.18),Vector3(.027,.031,.030),Color("263f3a"),6,4)
		for ridge in range(6):
			var y: float = .46+ridge*.105
			_tube(s,Vector3(side*.055,y,-.01),Vector3(side*.10,y,.13),.010,.012,Color("ebd49c"),4)
	var curl := PackedVector3Array([Vector3(0,.38,.15),Vector3(0,.22,.16),Vector3(0,.10,.27),Vector3(0,.09,.43),Vector3(0,.18,.51),Vector3(0,.28,.46),Vector3(0,.28,.35),Vector3(0,.21,.33)])
	_curve(s,curl,.036,.009,Color("bd9f5f"))
	for spike in range(5):
		var y: float = .65+spike*.115
		_cone(s,Vector3(0,y,.15),Vector3(0,y+.055,.22),.027,Color("dfca90"))
	_cone(s,Vector3(0,1.17,-.12),Vector3(0,1.29,-.10),.042,Color("e1c78d"))
	_leaf(s,Vector3(0,.60,.15),Vector3(0,.86,.32),Vector3(0,.71,.22),Color("d8c6a2"),1.0)

static func _cuttlefish(s: SurfaceTool) -> void:
	var mantle := PackedVector3Array([Vector3(0,.12,-.34),Vector3(0,.17,-.10),Vector3(0,.18,.23),Vector3(0,.13,.52),Vector3(0,.12,.66)])
	_swept(s,mantle,PackedVector2Array([Vector2(.23,.12),Vector2(.35,.17),Vector2(.30,.16),Vector2(.16,.08),Vector2(.02,.02)]),Color("b68a77"),12)
	for side: float in [-1.0,1.0]:
		for segment in range(10):
			var a: float = float(segment)/10.0
			var b: float = float(segment+1)/10.0
			var z0: float = lerpf(-.30,.59,a)
			var z1: float = lerpf(-.30,.59,b)
			var w0: float = .085+.18*sin(a*PI)
			var w1: float = .085+.18*sin(b*PI)
			_quad(s,Vector3(side*w0,.12,z0),Vector3(side*(w0+.14),.11,z0),Vector3(side*w1,.12,z1),Vector3(side*(w1+.14),.11,z1),Color("d9b39d"),1.0)
		_oval(s,Vector3(side*.20,.14,-.38),Vector3(.10,.11,.10),Color("d3ae95"),8,5)
		_oval(s,Vector3(side*.275,.16,-.40),Vector3(.018,.045,.055),Color("24433f"),6,4)
	for arm in range(8):
		var side: float = (float(arm)-3.5)/3.5
		var tentacle := PackedVector3Array([Vector3(side*.21,.10,-.39),Vector3(side*.27,.07,-.61),Vector3(side*.32,.09,-.79),Vector3(side*.26,.15,-.91)])
		_curve(s,tentacle,.032,.009,Color("c49f88"),.8)
	for stripe in range(8):
		var z: float = -.15+stripe*.085
		_tube(s,Vector3(-.23,.29,z),Vector3(.23,.29,z+.015),.006,.006,Color("765f61"),4)

static func _turtle(s: SurfaceTool) -> void:
	# Oval vaulted shell with individually shaded scutes and a pale plastron.
	_oval(s,Vector3(0,.22,0),Vector3(.63,.25,.86),Color("9f9d65"),16,6)
	for ring in range(5):
		var a: float = float(ring)*PI*.5/5.0
		var b: float = float(ring+1)*PI*.5/5.0
		for sector in range(16):
			var u: float = float(sector)*TAU/16.0
			var v: float = float(sector+1)*TAU/16.0
			var color: Color = Color("61745a").lerp(Color("aaa272"),float((sector+ring*3)%5)/5.0)
			var p := Vector3(cos(u)*cos(a)*.66,.24+sin(a)*.40,sin(u)*cos(a)*.90)
			var q := Vector3(cos(v)*cos(a)*.66,.24+sin(a)*.40,sin(v)*cos(a)*.90)
			var r := Vector3(cos(u)*cos(b)*.66,.24+sin(b)*.40,sin(u)*cos(b)*.90)
			var t := Vector3(cos(v)*cos(b)*.66,.24+sin(b)*.40,sin(v)*cos(b)*.90)
			if ring<4:
				_quad(s,p,q,r,t,color)
			else:
				_triangle(s,p,q,r,color)
	_tube(s,Vector3(0,.22,-.64),Vector3(0,.22,-1.02),.16,.14,Color("8f9e75"),8)
	_oval(s,Vector3(0,.23,-1.10),Vector3(.19,.16,.26),Color("aab18a"),10,6)
	for side: float in [-1.0,1.0]:
		_oval(s,Vector3(side*.16,.29,-1.19),Vector3(.023,.028,.025),Color("253d39"),6,4)
		_leaf(s,Vector3(side*.41,.20,-.43),Vector3(side*1.30,.06,-.12),Vector3(side*.83,.20,-.59),Color("88986c"),1.0)
		_leaf(s,Vector3(side*.39,.17,.55),Vector3(side*.77,.07,.88),Vector3(side*.62,.16,.55),Color("9ca37b"),.45)
		for line in range(3):
			_tube(s,Vector3(side*(.74+line*.10),.20-line*.018,-.42+line*.08),Vector3(side*(.89+line*.10),.16-line*.018,-.30+line*.07),.012,.008,Color("c0bd95"),4,1.0)
	_cone(s,Vector3(0,.16,.73),Vector3(0,.10,1.05),.055,Color("8d9b74"))

static func _triangle(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, motion: float = 0.0) -> void:
	s.set_color(Color(color.r,color.g,color.b,motion))
	for point: Vector3 in [a,b,c]:
		s.add_vertex(point)

static func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, motion: float = 0.0) -> void:
	_triangle(s,a,b,c,color,motion)
	_triangle(s,b,d,c,color,motion)

static func _oval(s: SurfaceTool, center: Vector3, radii: Vector3, color: Color, sectors: int = 10, rows: int = 5, motion: float = 0.0) -> void:
	for row in range(rows):
		var a: float = -PI*.5+float(row)*PI/rows
		var b: float = -PI*.5+float(row+1)*PI/rows
		for sector in range(sectors):
			var u: float = float(sector)*TAU/sectors
			var v: float = float(sector+1)*TAU/sectors
			var p: Vector3 = center+Vector3(cos(u)*cos(a),sin(a),sin(u)*cos(a))*radii
			var q: Vector3 = center+Vector3(cos(v)*cos(a),sin(a),sin(v)*cos(a))*radii
			var r: Vector3 = center+Vector3(cos(u)*cos(b),sin(b),sin(u)*cos(b))*radii
			var t: Vector3 = center+Vector3(cos(v)*cos(b),sin(b),sin(v)*cos(b))*radii
			if row > 0:
				_triangle(s,p,q,r,color,motion)
			if row < rows-1:
				_triangle(s,q,t,r,color,motion)

static func _tube(s: SurfaceTool, start: Vector3, finish: Vector3, radius0: float, radius1: float, color: Color, sides: int = 6, motion: float = 0.0) -> void:
	var axis: Vector3 = (finish-start).normalized()
	var right: Vector3 = axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.FORWARD).normalized()
	var up: Vector3 = axis.cross(right).normalized()
	for index in range(sides):
		var a: float = float(index)*TAU/sides
		var b: float = float(index+1)*TAU/sides
		var radial0: Vector3 = right*cos(a)+up*sin(a)
		var radial1: Vector3 = right*cos(b)+up*sin(b)
		var p: Vector3 = start+radial0*radius0
		var q: Vector3 = start+radial1*radius0
		var r: Vector3 = finish+radial0*radius1
		var t: Vector3 = finish+radial1*radius1
		_triangle(s,p,q,r,color,motion)
		if radius1 > 0.00001:
			_triangle(s,q,t,r,color,motion)

static func _cone(s: SurfaceTool, base: Vector3, tip: Vector3, radius: float, color: Color) -> void:
	_tube(s,base,tip,radius,0.0,color,5)

static func _curve(s: SurfaceTool, path: PackedVector3Array, radius0: float, radius1: float, color: Color, motion: float = 0.0) -> void:
	for index in range(path.size()-1):
		_tube(s,path[index],path[index+1],lerpf(radius0,radius1,float(index)/(path.size()-1)),lerpf(radius0,radius1,float(index+1)/(path.size()-1)),color,5,motion)

static func _swept(s: SurfaceTool, path: PackedVector3Array, radii: PackedVector2Array, color: Color, sides: int = 10, motion: float = 0.0) -> void:
	for segment in range(path.size()-1):
		var direction: Vector3 = (path[segment+1]-path[segment]).normalized()
		var right := Vector3.RIGHT
		var up: Vector3 = right.cross(direction).normalized()
		for index in range(sides):
			var a: float = float(index)*TAU/sides
			var b: float = float(index+1)*TAU/sides
			var p: Vector3 = path[segment]+right*cos(a)*radii[segment].x+up*sin(a)*radii[segment].y
			var q: Vector3 = path[segment]+right*cos(b)*radii[segment].x+up*sin(b)*radii[segment].y
			var r: Vector3 = path[segment+1]+right*cos(a)*radii[segment+1].x+up*sin(a)*radii[segment+1].y
			var t: Vector3 = path[segment+1]+right*cos(b)*radii[segment+1].x+up*sin(b)*radii[segment+1].y
			_quad(s,p,q,r,t,color.lightened(float(index%3)*.025),motion)

static func _leaf(s: SurfaceTool, base: Vector3, tip: Vector3, shoulder: Vector3, color: Color, motion: float = 0.0) -> void:
	var other: Vector3 = base.lerp(tip,.68)+(base.lerp(tip,.45)-shoulder)*.45
	var ridge: Vector3 = base.lerp(tip,.54)+Vector3.UP*.035
	_triangle(s,base,shoulder,ridge,color,motion*.35)
	_triangle(s,shoulder,tip,ridge,color.lightened(.12),motion)
	_triangle(s,tip,other,ridge,color,motion)
	_triangle(s,other,base,ridge,color.darkened(.08),motion*.65)
