extends RefCounted
## A continuous reef garden, batched into four shared, original coral meshes.
const Ocean = preload("res://scripts/ocean_config.gd")
const FORM_NAMES = ["Staghorn", "TableCoral", "SeaFan", "BrainCoral"]
const PALETTE = [Color("d48e78"), Color("ceb176"), Color("ac94bb"), Color("ce9aaa"), Color("80b7a3"), Color("d0b990"), Color("8bbac2"), Color("b5a2cf")]
const FOOTPRINT = Rect2(-45.0, -43.5, 90.0, 75.0)
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

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
	# Uneven reef patches with mixed ages, not rows of equally sized ornaments.
	var clusters: Array[Vector2] = []
	for side: float in [-1.0,1.0]:
		for row in range(4):
			clusters.append(Vector2(side*random.randf_range(16.0,32.0),-33.0+float(row)*19.0))
	var attempts := 0
	while positions.size() < 150 and attempts < 6000:
		attempts += 1
		var center: Vector2 = clusters[random.randi_range(0,clusters.size()-1)]
		var x: float = center.x+random.randfn(0,8.0)
		var z: float = center.y+random.randfn(0,7.0)
		if attempts%4 == 0:
			x = random.randf_range(-43.0,43.0)
			z = random.randf_range(-41.0,30.0)
		if not FOOTPRINT.grow(-1.0).has_point(Vector2(x,z)) or absf(x-sin((z+6.0)*.055)*6.0)<8.6:
			continue
		var clear := true
		for other: Vector3 in positions:
			if Vector2(x-other.x,z-other.z).length_squared()<5.0:
				clear = false
				break
		if not clear:
			continue
		var point := Vector3(x,Ocean.seabed_height(origin.x+x,origin.z+z)-origin.y,z)
		var form: int = positions.size()%FORM_NAMES.size()
		var size: float = random.randf_range(.55,1.17)
		var scale := Vector3(size*random.randf_range(.8,1.12),size*random.randf_range(.75,1.12),size)
		var dx: float = (Ocean.seabed_height(origin.x+x+.4,origin.z+z)-Ocean.seabed_height(origin.x+x-.4,origin.z+z))/.8
		var dz: float = (Ocean.seabed_height(origin.x+x,origin.z+z+.4)-Ocean.seabed_height(origin.x+x,origin.z+z-.4))/.8
		var normal := Vector3(-dx,1,-dz).normalized()
		var tilt := Basis(Quaternion(Vector3.UP,Vector3.UP.lerp(normal,.65).normalized()))
		transforms[form].append(Transform3D(tilt*Basis(Vector3.UP,random.randf_range(-PI,PI))*Basis.from_scale(scale),point))
		colors[form].append(PALETTE[random.randi_range(0,PALETTE.size()-1)])
		positions.append(point)
	var shared_material: ShaderMaterial = material()
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
		visual.material_override = shared_material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 175.0
		visual.visibility_range_end_margin = 20.0
		visual.extra_cull_margin = 0.4
		garden.add_child(visual)
	garden.set_meta("patch_count", positions.size())
	garden.set_meta("footprint", FOOTPRINT)
	garden.set_meta("patch_positions", positions)
	garden.set_meta("forms", PackedStringArray(FORM_NAMES))
	garden.set_meta("channel_width", 7.0)
	garden.set_meta("draw_batches", FORM_NAMES.size())
	garden.set_meta("organic_growth", true)

static func animate(time: float) -> void:
	for value: ShaderMaterial in _materials.values():
		value.set_shader_parameter("reef_clock",time)

static func material(tint: Color = Color.WHITE) -> ShaderMaterial:
	if _materials.has(tint):
		return _materials[tint]
	var result := ShaderMaterial.new()
	if not _materials.is_empty():
		result.shader = _materials.values()[0].shader
	else:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float reef_clock = 0.0;
varying vec3 coral_position;
float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
void vertex() {
    coral_position = VERTEX;
    // Only sea fans carry this flexibility mask. The holdfast stays planted.
    float h = max(VERTEX.y-0.16,0.0);
    float phase = MODEL_MATRIX[3].x*0.21+MODEL_MATRIX[3].z*0.16;
    float bend = sin(reef_clock*0.72+phase)*0.055+sin(reef_clock*1.13+phase*1.7)*0.018;
    VERTEX.x += UV2.x*h*h*bend;
    VERTEX.z += UV2.x*h*h*sin(reef_clock*0.61+phase)*0.022;
    NORMAL.y -= UV2.x*2.0*h*(bend*NORMAL.x+sin(reef_clock*0.61+phase)*0.022*NORMAL.z);
    NORMAL = normalize(NORMAL);
}
void fragment() {
    vec3 p = coral_position;
    float broad = sin(p.x * 3.7 + sin(p.z * 2.9)) * sin(p.y * 4.1 + p.z * 2.3);
    float detail = 1.0 - smoothstep(7.0, 28.0, length(VERTEX));
    vec3 cell = p * 23.0;
    float pore = hash31(floor(cell));
    float dot_shape = length(fract(cell).xy - vec2(0.5));
    float polyps = (1.0 - smoothstep(0.12, 0.28 + fwidth(dot_shape), dot_shape)) * step(0.48,pore);
    float growth = 1.0;
    if (COLOR.a < 0.7) {
        // Meandering fleshy ridges rather than a cracked polygon shell.
        vec2 w = p.xz*24.0;
        w += vec2(sin(w.y*0.65)+sin(w.x*0.43+w.y*0.36),cos(w.x*0.62))*0.95;
        float ridge = sin(w.x+sin(w.y*1.2)*1.5)*0.5+0.5;
        growth = 0.90+smoothstep(0.25,0.72,ridge)*0.12;
        float relief = smoothstep(0.1,0.85,ridge)*0.004*detail;
        vec3 s = cross(dFdy(VERTEX),NORMAL);
        vec3 t = cross(NORMAL,dFdx(VERTEX));
        float det = dot(dFdx(VERTEX),s);
        NORMAL = normalize(abs(det)*NORMAL-sign(det)*(dFdx(relief)*s+dFdy(relief)*t));
    }
    ALBEDO = COLOR.rgb * tint.rgb * (0.96 + broad * 0.045 - polyps * 0.065 * detail) * growth;
    if (COLOR.a > 0.75 && COLOR.a < 0.9) {
        ALBEDO = vec3(0.47,0.51,0.44)*(0.96+broad*0.06);
    }
    ROUGHNESS = 0.95;
    SPECULAR = 0.12;
}
"""
		result.shader = shader
	result.set_shader_parameter("tint",tint)
	_materials[tint] = result
	return result

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(vertex)

static func _tube(surface: SurfaceTool, start: Vector3, end: Vector3, bottom: float, top: float, color: Color) -> void:
	var direction: Vector3 = (end - start).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD if absf(direction.y) > 0.9 else Vector3.UP).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	for index in range(8):
		var a: float = float(index) * TAU / 8.0
		var b: float = float(index + 1) * TAU / 8.0
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
			# Irregular encrusted holdfasts merge into the seabed, without a round stand.
			for tri: Array in [[p,q,r],[q,s,r]]:
				for vertex: Vector3 in tri:
					var local: Vector3 = vertex-center
					var angle: float = atan2(local.z,local.x)
					var rim: float = 1.0+sin(angle*3.0)*.18+cos(angle*5.0)*.09
					surface.set_color(Color(color.r,color.g,color.b,.82))
					surface.add_vertex(center+Vector3(local.x*rim,local.y-.055,local.z*rim))

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
	# Small raised corallites break up the otherwise smooth table surface.
	for index in range(4):
		var angle: float = float(index) * 2.399
		var point: Vector3 = center + Vector3(cos(angle) * radius * 0.54, 0.235, sin(angle) * radius * 0.54)
		_cup(surface, point, 0.065, 0.055, Color("f4edda"), 5)

static func _cup(surface: SurfaceTool, base: Vector3, height: float, radius: float, color: Color, sides: int = 7) -> void:
	# Open tube, rolled lip and a shaded inner bowl, shared by polyps and sponges.
	for index in range(sides):
		var a: float = float(index) * TAU / float(sides)
		var b: float = float(index + 1) * TAU / float(sides)
		var da := Vector3(cos(a), 0, sin(a))
		var db := Vector3(cos(b), 0, sin(b))
		var lower_a: Vector3 = base + da * radius * 0.72
		var lower_b: Vector3 = base + db * radius * 0.72
		var rim_a: Vector3 = base + Vector3.UP * height + da * radius
		var rim_b: Vector3 = base + Vector3.UP * height + db * radius
		var inner_a: Vector3 = base + Vector3.UP * height + da * radius * 0.66
		var inner_b: Vector3 = base + Vector3.UP * height + db * radius * 0.66
		_triangle(surface, lower_a, rim_a, lower_b, color)
		_triangle(surface, lower_b, rim_a, rim_b, color)
		_triangle(surface, rim_a, rim_b, inner_a, color.lightened(0.18))
		_triangle(surface, rim_b, inner_b, inner_a, color.lightened(0.18))
		_triangle(surface, inner_a, inner_b, base + Vector3.UP * height * 0.70, color.darkened(0.50))

static func _coral_mesh(form: int) -> ArrayMesh:
	if _meshes.has(form):
		return _meshes[form]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_uv2(Vector2(1,0) if form == 2 else Vector2.ZERO)
	match form:
		0: _branch_colony(surface)
		1: _table_colony(surface)
		2: _fan_colony(surface)
		3: _brain_colony(surface)
	if form != 3:
		surface.generate_normals()
	_meshes[form] = surface.commit()
	return _meshes[form]

static func _growth_branch(surface: SurfaceTool, start: Vector3, direction: Vector3, length: float, radius: float, depth: int, random: RandomNumberGenerator) -> void:
	var bend := Vector3(random.randf_range(-0.17,0.17),random.randf_range(-0.03,0.12),random.randf_range(-0.17,0.17))
	var middle: Vector3 = start + direction * length * 0.53 + bend * length
	var end: Vector3 = middle + (direction+Vector3.UP*0.20+bend).normalized()*length*0.47
	_curved_branch(surface,start,middle,end,radius,radius*(.36 if depth == 0 else .62))
	if depth <= 0:
		_branch_tip(surface,end,radius*.38)
		return
	for fork in range(2):
		var angle: float = random.randf_range(-PI,PI)
		var lateral := Vector3(cos(angle),random.randf_range(0.35,0.80),sin(angle))
		var aim: Vector3 = (direction*0.42+lateral*0.64+Vector3.UP*0.31).normalized()
		_growth_branch(surface,end if fork == 0 else middle.lerp(end,0.40),aim,length*random.randf_range(0.47,0.66),radius*0.72,depth-1,random)

static func _branch_tip(surface: SurfaceTool, center: Vector3, radius: float) -> void:
	for ring in range(2):
		var a: float = float(ring)*PI/4.0
		var b: float = float(ring+1)*PI/4.0
		for sector in range(8):
			var c: float = float(sector)*TAU/8.0
			var d: float = float(sector+1)*TAU/8.0
			var p := center+Vector3(cos(c)*cos(a),sin(a),sin(c)*cos(a))*radius
			var q := center+Vector3(cos(d)*cos(a),sin(a),sin(d)*cos(a))*radius
			var r := center+Vector3(cos(c)*cos(b),sin(b),sin(c)*cos(b))*radius
			var s := center+Vector3(cos(d)*cos(b),sin(b),sin(d)*cos(b))*radius
			_triangle(surface,p,q,r,Color("e2d6b7"))
			_triangle(surface,q,s,r,Color("e2d6b7"))

static func _curved_branch(surface: SurfaceTool, start: Vector3, bend: Vector3, end: Vector3, bottom: float, top: float) -> void:
	# Continuous bent growth without a capped cylinder at each elbow.
	var direction: Vector3 = (end-start).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD if absf(direction.y)>.9 else Vector3.UP).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	for segment in range(4):
		var t0: float = float(segment)/4.0
		var t1: float = float(segment+1)/4.0
		var a: Vector3 = start.lerp(bend,t0).lerp(bend.lerp(end,t0),t0)
		var b: Vector3 = start.lerp(bend,t1).lerp(bend.lerp(end,t1),t1)
		for sector in range(8):
			var angle: float = float(sector)*TAU/8.0
			var next: float = float(sector+1)*TAU/8.0
			var p: Vector3 = side*cos(angle)+up*sin(angle)
			var q: Vector3 = side*cos(next)+up*sin(next)
			var r0: float = lerpf(bottom,top,t0)
			var r1: float = lerpf(bottom,top,t1)
			_triangle(surface,a+p*r0,b+p*r1,a+q*r0,Color("c9cbb0"))
			_triangle(surface,a+q*r0,b+p*r1,b+q*r1,Color("c9cbb0"))

static func _branch_colony(surface: SurfaceTool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 317729
	_dome(surface,Vector3.ZERO,Vector3(0.75,0.14,0.67),Color("aaa98f"))
	for stem in range(7):
		var a: float = float(stem)*2.399963
		var distance: float = sqrt(float(stem)/7.0)*0.80
		var root := Vector3(cos(a)*distance,0.06,sin(a)*distance)
		var direction := Vector3(cos(a)*0.54,random.randf_range(0.8,1.1),sin(a)*0.54).normalized()
		_growth_branch(surface,root,direction,random.randf_range(0.90,1.23),random.randf_range(0.055,0.088),2,random)

static func _table_point(center: Vector3, radius: float, angle: float, fraction: float, phase: float, lower: bool = false) -> Vector3:
	var rim: float = 1.0+sin(angle*3.0+phase)*0.11+sin(angle*7.0-phase)*0.035
	var x: float = cos(angle)*radius*fraction*rim
	var z: float = sin(angle)*radius*fraction*rim*0.79
	var y: float = fraction*fraction*0.36+sin(angle*3.0+phase)*fraction*0.14+sin(fraction*6.0+angle*7.0+phase)*0.045*fraction
	if lower:
		y -= 0.055+0.035*(1.0-fraction)
	return center+Vector3(x,y,z)

static func _organic_table(surface: SurfaceTool, center: Vector3, radius: float, phase: float) -> void:
	for sector in range(24):
		var a: float = float(sector)*TAU/24.0
		var b: float = float(sector+1)*TAU/24.0
		for ring in range(4):
			var f0: float = float(ring)/4.0
			var f1: float = float(ring+1)/4.0
			var p: Vector3 = _table_point(center,radius,a,f0,phase)
			var q: Vector3 = _table_point(center,radius,b,f0,phase)
			var r: Vector3 = _table_point(center,radius,a,f1,phase)
			var s: Vector3 = _table_point(center,radius,b,f1,phase)
			var color: Color = Color("c4c0a4").lerp(Color("e3ddbf"),pow(f1,4.0)*0.6)
			_triangle(surface,p,q,r,color)
			_triangle(surface,q,s,r,color)
			var u: Vector3 = _table_point(center,radius,a,f0,phase,true)
			var v: Vector3 = _table_point(center,radius,b,f0,phase,true)
			var w: Vector3 = _table_point(center,radius,a,f1,phase,true)
			var t: Vector3 = _table_point(center,radius,b,f1,phase,true)
			_triangle(surface,u,w,v,Color("929d8e"))
			_triangle(surface,v,w,t,Color("929d8e"))
			if ring == 3:
				_triangle(surface,r,s,w,Color("ded3af"))
				_triangle(surface,s,t,w,Color("ded3af"))

static func _table_colony(surface: SurfaceTool) -> void:
	# Offset tiers grow from a low knotted base, not from a single mushroom stem.
	_dome(surface,Vector3.ZERO,Vector3(1.0,0.23,0.74),Color("aaa98f"))
	for spec: Vector4 in [Vector4(-.70,.24,.10,1.10),Vector4(.62,.38,-.45,1.05),Vector4(-.32,.64,-.48,1.08),Vector4(.55,.70,.43,.90),Vector4(-.60,.88,.36,.85),Vector4(.04,1.12,-.10,.80)]:
		var center := Vector3(spec.x,spec.y,spec.z)
		_tube(surface,Vector3(spec.x*0.35,0.08,spec.z*0.3),center,0.17,0.08,Color("b2b398"))
		_organic_table(surface,center,spec.w,spec.x*3.0+spec.y*2.0)

static func _fan_point(column: int, row: int) -> Vector3:
	var u: float = float(column)/22.0*2.0-1.0
	var t: float = float(row)/12.0
	var width: float = 0.13+pow(t,0.70)*1.80
	var x: float = u*width+sin(t*4.5+u*2.1)*0.19*t+sin(float(column)*5.71+float(row)*3.43)*0.08*t
	var y: float = 0.18+t*(2.50-absf(u)*0.45)+sin(float(column)*2.3+float(row)*1.4)*0.055*t
	var z: float = sin(x*1.3+t*3.0)*t*0.16
	return Vector3(x,y,z)

static func _fan_colony(surface: SurfaceTool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 91331
	_dome(surface,Vector3.ZERO,Vector3(0.45,0.13,0.34),Color("a0a18d"))
	for row in range(12):
		for column in range(23):
			if row == 0 and column%2 == 1:
				continue
			var a: Vector3 = _fan_point(column,row)
			var b: Vector3 = _fan_point(column,row+1)
			var radius: float = lerpf(0.024,0.009,float(row)/12.0)
			_fine_branch(surface,a,b,radius,Color("d6c7bd"))
			if row > 1 and column < 22 and random.randf() > 0.26:
				var c: Vector3 = _fan_point(column+1,row+1 if (column+row)%3 == 0 else row)
				_fine_branch(surface,a,c,0.008,Color("d7c8ba"))
			if row > 4 and column < 22 and random.randf() > 0.77:
				_fine_branch(surface,a.lerp(b,0.45),_fan_point(column+1,row+1),0.009,Color("e0cfbe"))

static func _fine_branch(surface: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var direction: Vector3 = (b-a).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD if absf(direction.z) < 0.8 else Vector3.UP).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	for index in range(4):
		var t0: float = float(index)*TAU/4.0
		var t1: float = float(index+1)*TAU/4.0
		var p: Vector3 = side*cos(t0)+up*sin(t0)
		var q: Vector3 = side*cos(t1)+up*sin(t1)
		_triangle(surface,a+p*radius,b+p*radius*0.83,a+q*radius,color)
		_triangle(surface,a+q*radius,b+p*radius*0.83,b+q*radius*0.83,color)

static func _brain_point(latitude: float, longitude: float) -> Vector3:
	var x: float = cos(longitude)*cos(latitude)*1.53
	var z: float = sin(longitude)*cos(latitude)*1.35
	var uneven: float = 1.0+sin(longitude*3.0+latitude*4.0)*0.095+cos(longitude*5.0-latitude*3.0)*0.045
	var normal := Vector3(x/2.34,sin(latitude)/1.04,z/1.82).normalized()
	var relief: float = sin(x*10.0+sin(z*6.0))*cos(z*8.0+x*2.0)*0.015
	return Vector3(x*uneven,0.03+sin(latitude)*.88*(1.0+sin(longitude*3.0)*cos(latitude)*.12),z*uneven)+normal*relief

static func _brain_colony(surface: SurfaceTool) -> void:
	# Grooves are carved into the colony skin, rather than tubes laid over a ball.
	for row in range(28):
		var a: float = float(row)*PI/56.0
		var b: float = float(row+1)*PI/56.0
		for column in range(80):
			var c: float = float(column)*TAU/80.0
			var d: float = float(column+1)*TAU/80.0
			var p: Vector3 = _brain_point(a,c)
			var q: Vector3 = _brain_point(a,d)
			var r: Vector3 = _brain_point(b,c)
			var s: Vector3 = _brain_point(b,d)
			_brain_triangle(surface,p,q,r)
			_brain_triangle(surface,q,s,r)

static func _brain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point: Vector3 in [a,b,c]:
		surface.set_color(Color(0.83,0.83,0.70,0.45))
		surface.set_normal(Vector3(point.x/2.34,maxf(0.0,point.y-0.03)/1.08,point.z/1.82).normalized())
		surface.add_vertex(point)
