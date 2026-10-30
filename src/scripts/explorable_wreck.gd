extends Node3D
## A large steel transport wreck with traversable holds, machinery and a two-level bridge.
const Ocean = preload("res://scripts/ocean_config.gd")
const School = preload("res://scripts/wreck_fish_school.gd")
const SWIM_BOUNDS := AABB(Vector3(-5.0, 2.0, -25.0), Vector3(10.0, 7.0, 50.0))
const INTERIOR_BOUNDS := AABB(Vector3(-8.0, 0.8, -29.0), Vector3(16.0, 19.0, 58.0))
const LOCAL_ENTRANCES := [Vector3(0, 6, -32), Vector3(0, 6, 32), Vector3(-10, 6, 0), Vector3(10, 6, 0), Vector3(0, 13, 0)]
const TREASURE_LOCAL := Vector3(3.3, 16.82, 12.7)
static var _steel: ShaderMaterial
static var _shared_meshes: Dictionary = {}

static func build(parent: Node3D) -> Node3D:
	var root = load("res://scripts/explorable_wreck.gd").new()
	root.name = "ExplorableWreck"
	var parent_origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var world_origin: Vector3 = parent_origin + Vector3(0, 0, -3.0)
	var heading := Basis(Vector3.UP, deg_to_rad(-23.0))
	# Lift the keel above the highest actual triangle under the entire swim space.
	var ground := -INF
	for x in range(-10, 11, 2):
		for z in range(-32, 33, 2):
			var sample: Vector3 = world_origin + heading * Vector3(x, 0, z)
			ground = maxf(ground, Ocean.seabed_height(sample.x, sample.z))
	world_origin.y = ground + 0.45
	root.position = world_origin - parent_origin
	root.basis = heading
	parent.add_child(root)
	root.set_meta("world_transform", Transform3D(heading, world_origin))
	for part: String in ["HullPlating", "SteelFrames", "DeckAndBridge", "Bulkheads", "EngineRoom", "DeckEquipment"]:
		var mesh: ArrayMesh = _mesh(part)
		var visual := MeshInstance3D.new()
		visual.name = part
		visual.mesh = mesh
		visual.material_override = _material()
		visual.visibility_range_end = 205.0
		visual.visibility_range_end_margin = 22.0
		root.add_child(visual)
		var body := StaticBody3D.new()
		body.name = part + "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var exact: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		exact.backface_collision = true
		shape.shape = exact
		body.add_child(shape)
		root.add_child(body)
	root._build_lower_hull()
	var school: Node3D = School.new()
	school.name = "WreckFishSchool"
	root.add_child(school)
	school.setup(SWIM_BOUNDS, [AABB(Vector3(-4,2,-25),Vector3(8,6,11)), AABB(Vector3(-5,2,-11),Vector3(10,7,10)), AABB(Vector3(-5,2,1),Vector3(10,7,10)), AABB(Vector3(-3,2,14),Vector3(6,6,11))])
	var entrances: Array[Vector3] = []
	for entrance: Vector3 in LOCAL_ENTRANCES:
		entrances.append(root._world_position(entrance))
	var route: Array[Vector3] = []
	for z: float in [-34.0,-27.0,-18.0,-8.0,0.0,8.0,18.0,27.0,34.0]:
		route.append(root._world_position(Vector3(0, 6, z)))
	root.set_meta("world_transform", Transform3D(heading, world_origin))
	root.set_meta("entrances", entrances)
	root.set_meta("entrance_names", PackedStringArray(["船首破口", "船尾破口", "左舷破洞", "右舷破洞", "上方舱口"]))
	root.set_meta("interior_center", root._world_position(Vector3(0, 6, 0)))
	root.set_meta("interior_bounds", INTERIOR_BOUNDS)
	root.set_meta("local_swim_bounds", SWIM_BOUNDS)
	root.set_meta("safe_swim_route", route)
	root.set_meta("hull_length", 66.0)
	root.set_meta("hull_width", 18.0)
	root.set_meta("interior_clear_height", 10.0)
	root.set_meta("hollow", true)
	root.set_meta("draw_batches", 7 + int(school.get_meta("draw_batches", 2)))
	root.set_meta("collision_matches_mesh", true)
	root.set_meta("compartments",PackedStringArray(["前货舱","中部货舱","后货舱","机舱","上层船桥"]))
	root.set_meta("bridge_route",[root._world_position(Vector3(0,6,0)),root._world_position(Vector3(0,12,0)),root._world_position(Vector3(0,13,8)),root._world_position(Vector3(0,13,12))])
	root.set_meta("treasure_name", "船长的星海罗盘")
	root.set_meta("treasure_route",[root._world_position(Vector3(0,6,0)),root._world_position(Vector3(0,12,0)),root._world_position(Vector3(0,13,8)),root._world_position(Vector3(0,13,12)),root._world_position(Vector3(0,17,12)),root._world_position(Vector3(1.3,17,12.7))])
	return root

func treasure_position() -> Vector3:
	# Clear of the chart table even at the low point of the pickup's gentle bob.
	return _world_position(TREASURE_LOCAL)

func contains_point(world: Vector3, margin: float = 2.0) -> bool:
	# The small approach margin lets the following camera shorten before a doorway.
	var current_transform: Transform3D = global_transform if is_inside_tree() else get_meta("world_transform", self.transform)
	return INTERIOR_BOUNDS.grow(margin).has_point(current_transform.affine_inverse() * world)

func _world_position(point: Vector3) -> Vector3:
	var current_transform: Transform3D = global_transform if is_inside_tree() else get_meta("world_transform", self.transform)
	return current_transform * point

func _build_lower_hull() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The buried lower belly follows the slope, so the wreck rests in the sand.
	# Its flat upper surface lies below the hold floor and every swimming route.
	for segment in range(10):
		var z0: float = -15.0 + segment * 3.0
		var z1: float = z0 + 3.0
		var w0: float = _half_width(0.2, z0)
		var w1: float = _half_width(0.2, z1)
		var corners := PackedVector3Array()
		for local: Vector3 in [Vector3(-w0*0.25,0,z0),Vector3(w0*0.25,0,z0),Vector3(w0,0,z0),Vector3(-w0,0,z0),Vector3(-w1*0.25,0,z1),Vector3(w1*0.25,0,z1),Vector3(w1,0,z1),Vector3(-w1,0,z1)]:
			local *= Vector3(1.5,1.3,2.0)
			if corners.size() in [0, 1, 4, 5]:
				var world: Vector3 = _world_position(local)
				local.y = minf(-0.25, Ocean.seabed_height(world.x, world.z) - world.y - 0.22)
			corners.append(local)
		_prism(surface, corners, Color("8d927c"))
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var visual := MeshInstance3D.new()
	visual.name = "BuriedLowerHull"
	visual.mesh = mesh
	visual.material_override = _material()
	visual.visibility_range_end = 180.0
	visual.visibility_range_end_margin = 18.0
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "LowerHullCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var exact: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	exact.backface_collision = true
	shape.shape = exact
	body.add_child(shape)
	add_child(body)

static func _mesh(part: String) -> ArrayMesh:
	if _shared_meshes.has(part):
		return _shared_meshes[part]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match part:
		"HullPlating": _hull(surface)
		"SteelFrames": _ribs(surface)
		"DeckAndBridge": _deck(surface)
		"Bulkheads": _bulkheads(surface)
		"EngineRoom": _engine_room(surface)
		"DeckEquipment": _equipment(surface)
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	if part in ["HullPlating","SteelFrames"]:
		var scaled := SurfaceTool.new()
		scaled.begin(Mesh.PRIMITIVE_TRIANGLES)
		scaled.append_from(result,0,Transform3D(Basis.from_scale(Vector3(1.5,1.3,2.0)),Vector3.ZERO))
		result = scaled.commit()
	_shared_meshes[part] = result
	return result

static func _half_width(y: float, z: float) -> float:
	var beam: float = 3.8 + 2.2 * sin(clampf(y / 8.5, 0.0, 1.0) * PI * 0.65)
	var taper: float = 1.0 - 0.43 * pow(clampf(absf(z) / 15.0, 0.0, 1.0), 3.0)
	return beam * taper

static func _hull(surface: SurfaceTool) -> void:
	var heights := PackedFloat32Array([0.2, 1.35, 2.5, 3.6, 4.7, 5.8, 6.9, 8.1])
	for side: float in [-1.0, 1.0]:
		for band in range(heights.size() - 1):
			for segment in range(10):
				var z0: float = -15.0 + segment * 3.0 + 0.025
				var z1: float = z0 + 2.95
				# Both flanks have a six-metre breach with four metres of headroom.
				if segment in [4, 5] and band in [2, 3, 4, 5]:
					continue
				var y0: float = heights[band] + 0.025
				var y1: float = heights[band + 1] - 0.025
				var a: float = side * _half_width(y0, z0)
				var b: float = side * _half_width(y1, z0)
				var c: float = side * _half_width(y0, z1)
				var d: float = side * _half_width(y1, z1)
				var corners := PackedVector3Array([Vector3(a-0.14,y0,z0), Vector3(a+0.14,y0,z0), Vector3(b+0.14,y1,z0), Vector3(b-0.14,y1,z0), Vector3(c-0.14,y0,z1), Vector3(c+0.14,y0,z1), Vector3(d+0.14,y1,z1), Vector3(d-0.14,y1,z1)])
				_prism(surface, corners, Color("9d987f").lerp(Color("718b83"), float((segment + band) % 4) * 0.13))
	# Narrow steel plates follow the tapered lower hull. The center stays open.
	for segment in range(10):
		var z0: float = -15.0 + segment * 3.0
		var z1: float = z0 + 3.0
		for plank in range(8):
			var left: float = float(plank) / 4.0 - 1.0
			var right: float = float(plank + 1) / 4.0 - 1.0
			var w0: float = _half_width(0.2, z0)
			var w1: float = _half_width(0.2, z1)
			_prism(surface, PackedVector3Array([Vector3(left*w0,0,z0),Vector3(right*w0,0,z0),Vector3(right*w0,0.32,z0),Vector3(left*w0,0.32,z0),Vector3(left*w1,0,z1),Vector3(right*w1,0,z1),Vector3(right*w1,0.32,z1),Vector3(left*w1,0.32,z1)]), Color("929079"))
	_box(surface, Vector3(0, -0.32, 0), Vector3(0.65, 0.9, 30.0), Color("7a7e6d"))

static func _ribs(surface: SurfaceTool) -> void:
	for z: float in [-15.0, -12.0, -9.0, -6.0, -3.2, 3.2, 6.0, 9.0, 12.0, 15.0]:
		for side: float in [-1.0, 1.0]:
			for section in range(8):
				var y0: float = 0.35 + float(section) * 1.0
				var y1: float = y0 + 1.0
				var start := Vector3(side * (_half_width(y0, z) - 0.22), y0, z)
				var finish := Vector3(side * (_half_width(y1, z) - 0.22), y1, z)
				_beam(surface, start, finish, 0.32, 0.38, Color("adb29b"))
	# Torn steel ribs above the deck preserve the wreck's broken silhouette.
	for spec: Vector3 in [Vector3(-5.4,8.3,-6),Vector3(5.0,8.3,9),Vector3(-4.8,8.3,12)]:
		_beam(surface, spec, spec + Vector3(0.25, 1.25, 0.2), 0.25, 0.32, Color("9b9d85"))

static func _deck(surface: SurfaceTool) -> void:
	# The torn prow retains a pointed silhouette above and below its swim breach.
	for side: float in [-1.0,1.0]:
		for band: Vector2 in [Vector2(.5,2.7),Vector2(8.4,11.2)]:
			_prism(surface,PackedVector3Array([Vector3(side*5.1,band.x,-30),Vector3(side*5.4,band.x,-30),Vector3(side*5.4,band.y,-30),Vector3(side*5.1,band.y,-30),Vector3(side*.7,band.x,-36),Vector3(side*1.0,band.x,-36),Vector3(side*1.0,band.y,-36),Vector3(side*.7,band.y,-36)]),Color("859e98"))
	# Steel side decks and hatch coamings surround three open cargo holds.
	for segment in range(20):
		var z0: float = -30.0+float(segment)*3.0
		var z1: float = z0+3.0
		var w0: float = _half_width(8.2,z0*.5)*1.5
		var w1: float = _half_width(8.2,z1*.5)*1.5
		for side: float in [-1.0,1.0]:
			var a: float = side*minf(4.2,w0-.3)
			var b: float = side*minf(4.2,w1-.3)
			_prism(surface,PackedVector3Array([Vector3(a,10.65,z0),Vector3(side*w0,10.65,z0),Vector3(side*w0,11,z0),Vector3(a,11,z0),Vector3(b,10.65,z1),Vector3(side*w1,10.65,z1),Vector3(side*w1,11,z1),Vector3(b,11,z1)]),Color("879b99"))
		if absf((z0+z1)*.5)>26.0:
			_box(surface,Vector3(0,10.82,(z0+z1)*.5),Vector3(minf(w0,w1)*2,.35,3),Color("8c9d98"))
	for z: float in [-12.0,12.0]:
		_box(surface,Vector3(0,10.85,z),Vector3(15.3,.40,1.3),Color("91aaa6"))
	for side: float in [-1.0,1.0]:
		for z: float in [-20.0,0.0,20.0]:
			_box(surface,Vector3(side*4.25,11.28,z),Vector3(.22,.60,13.8),Color("b09579"))
	# Two accessible bridge levels: broad broken doors and open viewing windows.
	for level in range(2):
		var y: float = 11.15+float(level)*3.8
		var width: float = 5.6-float(level)*.6
		for side: float in [-1.0,1.0]:
			_box(surface,Vector3(side*width,y+.55,12.0),Vector3(.32,1.1,8.2),Color("95a9a4"))
			_box(surface,Vector3(side*width,y+2.9,12.0),Vector3(.32,.5,8.2),Color("95a9a4"))
			for window_z: float in [8,10,12,14,16]:
				_box(surface,Vector3(side*width,y+1.9,window_z),Vector3(.32,1.7,.18),Color("a3b3ab"))
			for z: float in [7.9,16.1]:
				_box(surface,Vector3(side*(width+1.8)*.5,y+1.5,z),Vector3(width-1.8,3.0,.3),Color("96aaa4"))
				_box(surface,Vector3(side*width,y+3.15,z),Vector3(.35,.6,.35),Color("aaab97"))
		for side: float in [-1.0,1.0]:
			_box(surface,Vector3(side*(width+1.8)*.5,y+3.55,12),Vector3(width-1.1,.3,8.8),Color("788e8d"))
		for z: float in [8.75,15.25]:
			_box(surface,Vector3(0,y+3.55,z),Vector3(3.0,.3,2.2),Color("788e8d"))
	# Chart table, instrument cabinet and wheel remain beside the ascent hatch.
	_box(surface,Vector3(3.3,15.7,12.7),Vector3(2.0,1.4,2.5),Color("8b9d8e"))
	_box(surface,Vector3(3.3,16.45,12.7),Vector3(2.2,.12,2.7),Color("a8b7a1"))
	_box(surface,Vector3(-3.2,15.8,9.7),Vector3(1.7,1.6,.8),Color("779a96"))
	for spoke in range(16):
		var a: float = float(spoke)*TAU/16.0
		var b: float = float(spoke+1)*TAU/16.0
		var center := Vector3(-3.2,16.9,10.3)
		_beam(surface,center+Vector3(cos(a),sin(a),0)*.65,center+Vector3(cos(b),sin(b),0)*.65,.065,.065,Color("b6a37f"))
		if spoke%4 == 0:
			_beam(surface,center,center+Vector3(cos(a),sin(a),0)*.8,.05,.05,Color("b6a37f"))
	for side: float in [-1.0,1.0]:
		for z in range(-26,28,4):
			if abs(z)<6 or (side>0 and z>14):
				continue
			var x: float = side*(_half_width(8.2,float(z)*.5)*1.5-.2)
			_beam(surface,Vector3(x,11,float(z)),Vector3(x,12.05,float(z)),.075,.075,Color("98aaa0"))
			var next_x: float = side*(_half_width(8.2,float(z+3)*.5)*1.5-.2)
			_beam(surface,Vector3(x,12,float(z)),Vector3(next_x,12,float(z+3)),.065,.065,Color("98aaa0"))

static func _bulkheads(surface: SurfaceTool) -> void:
	for z: float in [-12.0,12.0]:
		for side: float in [-1.0,1.0]:
			_box(surface,Vector3(side*5.45,5.35,z),Vector3(4.7,10.0,.35),Color("82998f"))
		_box(surface,Vector3(0,9.95,z),Vector3(6.2,1.0,.38),Color("9da78f"))
	# Cargo frames stay beside the centre lane and below the fish volumes.
	for side: float in [-1.0,1.0]:
		for z: float in [-20.0,-6.0,6.0]:
			var x: float = side*6.3
			_box(surface,Vector3(x,1.45,z),Vector3(1.7,2.2,2.3),Color("b5a17b"))
			for level: float in [.65,2.1]:
				_box(surface,Vector3(x,level,z),Vector3(1.84,.12,2.4),Color("5e7773"))

static func _engine_room(surface: SurfaceTool) -> void:
	for side: float in [-1.0,1.0]:
		_cylinder(surface,Vector3(side*5.15,3.0,17),Vector3(side*5.15,3.0,24),1.45,Color("8b9d91"))
		for z: float in [17.5,20,22.5]:
			_box(surface,Vector3(side*5.15,1.0,z),Vector3(3.1,1.2,.45),Color("ac9477"))
			_cylinder(surface,Vector3(side*5.15,4.3,z),Vector3(side*5.15,7.8,z),.18,Color("a8a08a"))
		_cylinder(surface,Vector3(side*6.7,8.3,14),Vector3(side*6.7,8.3,26),.22,Color("aaa38c"))
		_box(surface,Vector3(side*5.5,7.5,26),Vector3(2.1,2.0,.6),Color("738f8b"))
		for x: float in [-.55,0,.55]:
			_cylinder(surface,Vector3(side*5.5+x,7.7,25.65),Vector3(side*5.5+x,7.7,25.5),.16,Color("bdc5af"))

static func _equipment(surface: SurfaceTool) -> void:
	# A worn funnel, cargo derricks, winches, vents and aft screw define the era.
	_cylinder(surface,Vector3(-3.4,11.1,19.5),Vector3(-3.4,18.4,19.5),1.25,Color("a18b70"))
	_cylinder(surface,Vector3(-3.4,18.4,19.5),Vector3(-3.4,19.3,19.5),1.32,Color("546f6e"))
	for z: float in [-20.0,-7.0]:
		_cylinder(surface,Vector3(-6.4,11,z),Vector3(-7.2,23,z+1),.23,Color("97a6a1"))
		_beam(surface,Vector3(-7,18,z),Vector3(3.6,13.6,z+3),.24,.24,Color("9a9f8b"))
		_beam(surface,Vector3(-7.2,23,z+1),Vector3(3.6,13.6,z+3),.035,.035,Color("647d79"))
		_cylinder(surface,Vector3(5.6,12,z-.8),Vector3(5.6,12,z+.8),.62,Color("ac9277"))
		_box(surface,Vector3(5.6,11.35,z),Vector3(2.0,.5,2.1),Color("718c87"))
	for side: float in [-1.0,1.0]:
		for z: float in [-25,-16,3,23]:
			_cylinder(surface,Vector3(side*6.2,11,z),Vector3(side*6.2,13,z),.28,Color("92a99f"))
			_cylinder(surface,Vector3(side*6.2,13,z),Vector3(side*5.5,13,z),.36,Color("a3b6ab"))
	_cylinder(surface,Vector3(0,1,29),Vector3(0,1,33),.38,Color("8d9279"))
	for blade in range(4):
		var angle: float = float(blade)*TAU/4.0
		_beam(surface,Vector3(0,1,32.6),Vector3(cos(angle)*2.5,1+sin(angle)*2.5,33.1),.85,.18,Color("9c9d7b"))
	_box(surface,Vector3(0,1.3,34),Vector3(.22,3.5,2.0),Color("7b938b"))
	# Torn steel around the side breaches, clear of the swimmer's centre line.
	for side: float in [-1.0,1.0]:
		for z: float in [-6.0,6.0]:
			_beam(surface,Vector3(side*8.2,8.7,z),Vector3(side*10,9.3,z+1.2),.16,1.0,Color("ba9875"))

static func _cylinder(surface: SurfaceTool, start: Vector3, finish: Vector3, radius: float, tint: Color) -> void:
	var axis: Vector3 = (finish-start).normalized()
	var right: Vector3 = axis.cross(Vector3.FORWARD if absf(axis.z)<.9 else Vector3.UP).normalized()
	var up: Vector3 = axis.cross(right).normalized()
	for side in range(12):
		var a: float = float(side)*TAU/12.0
		var b: float = float(side+1)*TAU/12.0
		var p: Vector3 = (right*cos(a)+up*sin(a))*radius
		var q: Vector3 = (right*cos(b)+up*sin(b))*radius
		for point: Vector3 in [start+p,finish+p,start+q,start+q,finish+p,finish+q,start,start+q,start+p,finish,finish+p,finish+q]:
			surface.set_color(tint)
			surface.add_vertex(point)

static func _beam(surface: SurfaceTool, start: Vector3, finish: Vector3, width: float, depth: float, tint: Color) -> void:
	var direction: Vector3 = (finish - start).normalized()
	var right: Vector3 = direction.cross(Vector3.FORWARD if absf(direction.z) < 0.9 else Vector3.UP).normalized() * width * 0.5
	var front: Vector3 = direction.cross(right).normalized() * depth * 0.5
	_prism(surface, PackedVector3Array([start-right-front,start+right-front,finish+right-front,finish-right-front,start-right+front,start+right+front,finish+right+front,finish-right+front]), tint)

static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, tint: Color) -> void:
	var corners := PackedVector3Array()
	for offset: Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:
		corners.append(center + offset * size * 0.5)
	_prism(surface, corners, tint)

static func _prism(surface: SurfaceTool, corners: PackedVector3Array, tint: Color) -> void:
	for face: Array in [[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]]:
		for index: int in [face[0],face[2],face[1],face[0],face[3],face[2]]:
			surface.set_color(tint)
			surface.add_vertex(corners[index])

static func _material() -> ShaderMaterial:
	if _steel != null:
		return _steel
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 steel_position;
varying vec3 steel_normal;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise21(vec2 p) {
    vec2 c=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(c),hash21(c+vec2(1,0)),f.x),mix(hash21(c+vec2(0,1)),hash21(c+vec2(1)),f.x),f.y);
}
void vertex() { steel_position=VERTEX; steel_normal=NORMAL; }
void fragment() {
    vec3 p=steel_position;
    vec2 uv=abs(steel_normal.y)>.65?p.xz:(abs(steel_normal.z)>.65?p.xy:p.zy);
    float rust=smoothstep(.38,.76,noise21(uv*.6)+noise21(uv*2.6)*.22);
    vec2 cell=fract(uv/vec2(3.0,1.5));
    float edge=min(min(cell.x,1.0-cell.x),min(cell.y,1.0-cell.y));
    float seam=1.0-smoothstep(.002,.012+fwidth(edge),edge);
    vec2 rivet=vec2(fract(uv.x*3.0)-.5,fract(uv.y/1.5)-.045);
    float stud=1.0-smoothstep(.025,.05,length(rivet));
    vec3 painted=COLOR.rgb*vec3(.67,.80,.79);
    ALBEDO=mix(painted,vec3(.45,.28,.17),rust*.55)*(1.0-seam*.16)+stud*.035;
    ROUGHNESS=.95;
    SPECULAR=.16;
}
"""
	_steel = ShaderMaterial.new()
	_steel.shader = shader
	return _steel
