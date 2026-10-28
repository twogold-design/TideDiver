extends RefCounted
## A continuous reef garden, batched into four shared, original coral meshes.
const Ocean = preload("res://scripts/ocean_config.gd")
const FORM_NAMES = ["Staghorn", "TableCoral", "SeaFan", "BrainCoral"]
const PALETTE = [Color("c4a38e"), Color("bcb493"), Color("b4a0ac"), Color("bf9f95"), Color("97afa2"), Color("cec1a4"), Color("8eaaa5"), Color("bea28a")]
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
	for row in range(10):
		for column in range(18):
			var x: float = (float(column) - 8.5) * 4.8 + random.randf_range(-0.8, 0.8)
			var z: float = (float(row) - 4.5) * 7.2 - 6.0 + random.randf_range(-1.25, 1.25)
			# A seven-metre winding sand lane remains open between the living banks.
			if absf(x - sin((z + 6.0) * 0.055) * 6.0) < 7.0:
				continue
			# Small coherent shifts break the planting rows without sacrificing the
			# central sand route or the authored number of colonies.
			var side: float = signf(x - sin((z + 6.0) * 0.055) * 6.0)
			x += sin(x * 0.37 + z * 0.13) * 1.2
			z += sin(x * 0.21 - z * 0.28) * 1.5
			var lane: float = sin((z + 6.0) * 0.055) * 6.0
			x = lane + side * maxf(absf(x - lane), 8.3)
			var point := Vector3(x, Ocean.seabed_height(origin.x + x, origin.z + z) - origin.y, z)
			var form: int = posmod(column + row * 3, FORM_NAMES.size())
			var yaw: float = random.randf_range(-PI, PI)
			var size: float = random.randf_range(0.92, 1.22)
			var scale := Vector3(size * (0.84 + 0.14 * sin(x * 0.19)), random.randf_range(0.78, 1.18), size)
			var dx: float = (Ocean.seabed_height(origin.x+x+0.4,origin.z+z)-Ocean.seabed_height(origin.x+x-0.4,origin.z+z))/0.8
			var dz: float = (Ocean.seabed_height(origin.x+x,origin.z+z+0.4)-Ocean.seabed_height(origin.x+x,origin.z+z-0.4))/0.8
			var normal := Vector3(-dx,1,-dz).normalized()
			var tilt := Basis(Quaternion(Vector3.UP,Vector3.UP.lerp(normal,0.65).normalized()))
			transforms[form].append(Transform3D((tilt * Basis(Vector3.UP, yaw)).scaled(scale), point))
			colors[form].append(PALETTE[posmod(column + row * 3 + int(column / 4), PALETTE.size())])
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
		garden.add_child(visual)
	garden.set_meta("patch_count", positions.size())
	garden.set_meta("footprint", FOOTPRINT)
	garden.set_meta("patch_positions", positions)
	garden.set_meta("forms", PackedStringArray(FORM_NAMES))
	garden.set_meta("channel_width", 7.0)
	garden.set_meta("draw_batches", FORM_NAMES.size())
	garden.set_meta("organic_growth", true)

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
varying vec3 coral_position;
float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
vec2 cell_hash(vec2 p) {
    return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3)))) * 43758.5453);
}
float brain_ridges(vec3 p) {
    vec2 cells = p.xz * vec2(5.2,3.7);
    cells += vec2(sin(p.z*4.3+p.x*1.6),sin(p.x*3.9-p.z*1.2)) * 0.65;
    vec2 cell = floor(cells);
    vec2 f = fract(cells);
    float nearest = 10.0;
    float second = 10.0;
    for (int y=-1; y<=1; y++) {
        for (int x=-1; x<=1; x++) {
            vec2 offset = vec2(float(x),float(y));
            float d = length(offset + 0.15 + cell_hash(cell+offset)*0.70 - f);
            if (d < nearest) { second = nearest; nearest = d; }
            else if (d < second) { second = d; }
        }
    }
    return 1.0 - smoothstep(0.025,0.16,second-nearest);
}
void vertex() { coral_position = VERTEX; }
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
        growth = 0.72 + brain_ridges(p) * 0.31;
    }
    ALBEDO = COLOR.rgb * tint.rgb * (0.96 + broad * 0.045 - polyps * 0.065 * detail) * growth;
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
	for index in range(6):
		var a: float = float(index) * TAU / 6.0
		var b: float = float(index + 1) * TAU / 6.0
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
			_triangle(surface, p, q, r, color)
			_triangle(surface, q, s, r, color)

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
	_tube(surface,start,middle,radius,radius*0.82,Color("bfc4ad"))
	_tube(surface,middle,end,radius*0.82,radius*0.62,Color("d7d5bb"))
	if depth <= 0:
		_tube(surface,end,end+direction*0.055,radius*0.64,radius*0.58,Color("fff3d5"))
		return
	for fork in range(2):
		var angle: float = random.randf_range(-PI,PI)
		var lateral := Vector3(cos(angle),random.randf_range(0.35,0.80),sin(angle))
		var aim: Vector3 = (direction*0.42+lateral*0.64+Vector3.UP*0.31).normalized()
		_growth_branch(surface,end if fork == 0 else middle.lerp(end,0.40),aim,length*random.randf_range(0.47,0.66),radius*0.72,depth-1,random)

static func _branch_colony(surface: SurfaceTool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 317729
	_dome(surface,Vector3.ZERO,Vector3(0.75,0.14,0.67),Color("aaa98f"))
	for stem in range(12):
		var a: float = float(stem)*2.399963
		var distance: float = sqrt(float(stem)/12.0)*0.70
		var root := Vector3(cos(a)*distance,0.06,sin(a)*distance)
		var direction := Vector3(cos(a)*0.54,random.randf_range(0.8,1.1),sin(a)*0.54).normalized()
		_growth_branch(surface,root,direction,random.randf_range(0.68,0.98),random.randf_range(0.095,0.135),2,random)

static func _table_point(center: Vector3, radius: float, angle: float, fraction: float, phase: float, lower: bool = false) -> Vector3:
	var rim: float = 1.0+sin(angle*3.0+phase)*0.11+sin(angle*7.0-phase)*0.035
	var x: float = cos(angle)*radius*fraction*rim
	var z: float = sin(angle)*radius*fraction*rim*0.79
	var y: float = fraction*0.11+sin(angle*2.0+phase)*fraction*0.11+sin(fraction*6.0+angle*4.0)*0.025*fraction
	if lower:
		y -= 0.055+0.035*(1.0-fraction)
	return center+Vector3(x,y,z)

static func _organic_table(surface: SurfaceTool, center: Vector3, radius: float, phase: float) -> void:
	for sector in range(32):
		var a: float = float(sector)*TAU/32.0
		var b: float = float(sector+1)*TAU/32.0
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
	for spec: Vector4 in [Vector4(-0.64,0.42,0.10,1.25),Vector4(0.55,0.72,-0.34,1.56),Vector4(-0.48,1.05,-0.08,1.60),Vector4(0.42,1.38,0.33,1.20)]:
		var center := Vector3(spec.x,spec.y,spec.z)
		_tube(surface,Vector3(spec.x*0.35,0.08,spec.z*0.3),center,0.17,0.08,Color("b2b398"))
		_organic_table(surface,center,spec.w,spec.x*3.0+spec.y*2.0)

static func _fan_point(column: int, row: int) -> Vector3:
	var u: float = float(column)/14.0*2.0-1.0
	var t: float = float(row)/11.0
	var width: float = 0.13+pow(t,0.70)*1.80
	var x: float = u*width+sin(t*4.5+u*2.1)*0.12*t+sin(float(column)*5.71+float(row)*3.43)*0.04*t
	var y: float = 0.18+t*(2.50-absf(u)*0.45)+sin(float(column)*2.3+float(row)*1.4)*0.055*t
	var z: float = sin(x*1.3+t*3.0)*t*0.16
	return Vector3(x,y,z)

static func _fan_colony(surface: SurfaceTool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 91331
	_dome(surface,Vector3.ZERO,Vector3(0.45,0.13,0.34),Color("a0a18d"))
	for row in range(11):
		for column in range(15):
			if row == 0 and column%2 == 1:
				continue
			var a: Vector3 = _fan_point(column,row)
			var b: Vector3 = _fan_point(column,row+1)
			var radius: float = lerpf(0.035,0.014,float(row)/11.0)
			_fine_branch(surface,a,b,radius,Color("d6c7bd"))
			if row > 1 and column < 14 and random.randf() > 0.10:
				var c: Vector3 = _fan_point(column+1,row+1 if (column+row)%3 == 0 else row)
				_fine_branch(surface,a,c,0.013,Color("d7c8ba"))
			if row > 4 and column < 14 and random.randf() > 0.69:
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
	var uneven: float = 1.0+sin(longitude*3.0+latitude*4.0)*0.035+cos(longitude*5.0-latitude*3.0)*0.022
	var normal := Vector3(x/2.34,sin(latitude)/1.04,z/1.82).normalized()
	var relief: float = sin(x*10.0+sin(z*6.0))*cos(z*8.0+x*2.0)*0.015
	return Vector3(x*uneven,0.03+sin(latitude)*1.04,z*uneven)+normal*relief

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
