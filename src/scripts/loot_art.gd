extends RefCounted
## Small shared meshes for seabed finds and a genuinely hinged, hollow chest.
const KINDS := ["sea_glass","ancient_coin","amber_shard","conch","captain_astrolabe","seagrass"]
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func supports(kind: String) -> bool:
	return kind in KINDS or kind in ["chest","treasure"]

static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "PickupArt"
	root.set_meta("pickup_kind",kind)
	if kind in ["chest","treasure"]:
		_visual(root,"ChestBase",_mesh("ChestBase"),"wood")
		var lid := Node3D.new()
		lid.name = "Lid"
		lid.position = Vector3(0,0.76,0.52)
		root.add_child(lid)
		_visual(lid,"HingedLid",_mesh("ChestLid"),"wood")
		var contents: MeshInstance3D = _visual(root,"Contents",_mesh("ChestContents"),"ancient_coin")
		contents.visible = false
		root.set_meta("openable_chest",true)
		root.set_meta("open",false)
	else:
		_visual(root,"Relic",_mesh(kind),kind)
		if kind == "captain_astrolabe":
			_visual(root,"StarCrystal",_mesh("StarCrystal"),"star_glow")
			root.set_meta("special_treasure",true)
	root.set_meta("decorative_collision",false)
	return root

static func set_chest_open(root: Node3D, opened: bool = true) -> void:
	var lid: Node3D = root.get_node_or_null("Lid")
	if lid == null:
		return
	lid.rotation.x = 1.15 if opened else 0.0
	root.set_meta("open",opened)
	var contents: Node3D = root.get_node_or_null("Contents")
	if contents != null:
		contents.visible = opened

static func _visual(parent: Node3D, label: String, mesh: Mesh, kind: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = _material(kind)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual

static func _material(kind: String) -> StandardMaterial3D:
	if not _materials.has(kind):
		var result := StandardMaterial3D.new()
		result.vertex_color_use_as_albedo = true
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
		result.roughness = 0.68
		if kind == "sea_glass":
			result.roughness = 0.24
			result.metallic_specular = 0.65
		elif kind == "ancient_coin":
			result.metallic = 0.5
			result.roughness = 0.5
		elif kind == "amber_shard":
			result.roughness = 0.3
		elif kind == "captain_astrolabe":
			result.metallic = 0.72
			result.roughness = 0.32
		elif kind == "star_glow":
			result.emission_enabled = true
			result.emission = Color("8bdfdf")
			result.emission_energy_multiplier = 0.7
		_materials[kind] = result
	return _materials[kind]

static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"sea_glass":
			_gem(surface,Vector3(-0.18,0.18,0.02),Vector3(0.64,0.32,0.43),Color("8ac4ba"),0.1)
			_gem(surface,Vector3(0.25,0.12,0.16),Vector3(0.34,0.22,0.31),Color("a8d3c3"),1.2)
			_gem(surface,Vector3(0.08,0.13,-0.28),Vector3(0.30,0.24,0.35),Color("83b4bd"),2.4)
		"ancient_coin":
			_coin(surface,Vector3(-0.14,0.07,0),0.35)
			_coin(surface,Vector3(0.21,0.06,0.17),0.27)
			_coin(surface,Vector3(0.06,0.13,-0.15),0.29)
		"amber_shard":
			_gem(surface,Vector3(0,0.36,0),Vector3(0.58,0.74,0.48),Color("d8a34e"),0.8)
			_tube(surface,Vector3(-0.10,0.23,-0.22),Vector3(0.08,0.45,-0.19),0.012,Color("826331"))
			_tube(surface,Vector3(0.02,0.37,-0.21),Vector3(0.12,0.36,-0.20),0.010,Color("826331"))
		"conch": _conch(surface)
		"captain_astrolabe": _astrolabe(surface)
		"StarCrystal":
			_gem(surface,Vector3(0,.64,0),Vector3(.30,.43,.30),Color("a5e4dc"),0.0)
		"seagrass":
			for strand in range(8):
				var x: float = (float(strand)-3.5)*.065
				for segment in range(5):
					var a: float = float(segment)*.18
					var b: float = a+.18
					var start := Vector3(x+sin(a*4+strand)*.08,a,.04*strand)
					var finish := Vector3(x+sin(b*4+strand)*.08,b,.04*strand)
					_triangle(surface,start-Vector3.RIGHT*.04,finish-Vector3.RIGHT*.025,start+Vector3.RIGHT*.04,Color("739866"))
					_triangle(surface,start+Vector3.RIGHT*.04,finish-Vector3.RIGHT*.025,finish+Vector3.RIGHT*.025,Color("9dbb7b"))
			_tube(surface,Vector3(-.3,.32,.13),Vector3(.3,.32,.13),.035,Color("c5b48a"))
		"ChestBase": _chest_base(surface)
		"ChestLid": _chest_lid(surface)
		"ChestContents":
			_coin(surface,Vector3(-0.2,0.24,-0.1),0.22)
			_coin(surface,Vector3(0.2,0.22,0.08),0.20)
			_gem(surface,Vector3(0.02,0.27,0),Vector3(0.19,0.24,0.19),Color("8ebbb1"),0.5)
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	_meshes[kind] = result
	return result

static func _astrolabe(surface: SurfaceTool) -> void:
	# A brass navigation instrument with concentric engraved rings and a compass rose.
	_coin(surface,Vector3(0,.10,0),.65)
	for ring in range(3):
		var radius: float = .36+float(ring)*.13
		for side in range(48):
			var a: float = float(side)*TAU/48.0
			var b: float = float(side+1)*TAU/48.0
			_tube(surface,Vector3(cos(a)*radius,.25,sin(a)*radius),Vector3(cos(b)*radius,.25,sin(b)*radius),.025,Color("dbc285"))
	for spoke in range(8):
		var angle: float = float(spoke)*TAU/8.0
		var length: float = .48 if spoke%2 == 0 else .30
		var forward := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))*.09
		var center := Vector3(0,.28,0)
		_triangle(surface,center-side,center+forward*length,center+side,Color("e8d19a") if spoke%2 == 0 else Color("79a8a1"))
	for side in range(40):
		var a: float = float(side)*TAU/40.0
		var b: float = float(side+1)*TAU/40.0
		_tube(surface,Vector3(cos(a)*.65,.73+sin(a)*.65,0),Vector3(cos(b)*.65,.73+sin(b)*.65,0),.035,Color("bfa46a"))
	_tube(surface,Vector3(0,.2,0),Vector3(0,.48,0),.06,Color("cfb579"))

static func _gem(surface: SurfaceTool, center: Vector3, size: Vector3, tint: Color, phase: float) -> void:
	for side in range(7):
		var a: float = float(side)*TAU/7.0
		var b: float = float(side+1)*TAU/7.0
		var p: Vector3 = center+Vector3(cos(a)*(0.46+sin(a*3.0+phase)*0.04),-0.19,sin(a)*0.45)*size
		var q: Vector3 = center+Vector3(cos(b)*(0.46+sin(b*3.0+phase)*0.04),-0.19,sin(b)*0.45)*size
		var r: Vector3 = center+Vector3(cos(a)*0.34,0.24,sin(a)*0.35)*size
		var s: Vector3 = center+Vector3(cos(b)*0.34,0.24,sin(b)*0.35)*size
		var color: Color = tint.lightened(float(side%3)*0.055)
		_triangle(surface,p,r,q,color)
		_triangle(surface,q,r,s,color)
		_triangle(surface,center+Vector3.UP*size.y*0.50,s,r,color.lightened(0.13))
		_triangle(surface,center-Vector3.UP*size.y*0.40,p,q,color.darkened(0.10))

static func _coin(surface: SurfaceTool, center: Vector3, radius: float) -> void:
	for side in range(20):
		var a: float = float(side)*TAU/20.0
		var b: float = float(side+1)*TAU/20.0
		var p: Vector3 = center+Vector3(cos(a)*radius,-0.035,sin(a)*radius)
		var q: Vector3 = center+Vector3(cos(b)*radius,-0.035,sin(b)*radius)
		var r: Vector3 = p+Vector3.UP*0.07
		var s: Vector3 = q+Vector3.UP*0.07
		var gold := Color("b7a06c") if side%4 else Color("7c9b80")
		_triangle(surface,center+Vector3.UP*0.035,s,r,gold)
		_triangle(surface,p,r,q,gold.darkened(0.12))
		_triangle(surface,q,r,s,gold.darkened(0.12))
		_triangle(surface,center-Vector3.UP*0.035,p,q,gold.darkened(0.15))
		_tube(surface,center+Vector3(cos(a)*radius*0.86,0.047,sin(a)*radius*0.86),center+Vector3(cos(b)*radius*0.86,0.047,sin(b)*radius*0.86),0.012,Color("cec18e"))
	for side in range(10):
		var a: float = float(side)*TAU/10.0
		var b: float = float(side+1)*TAU/10.0
		var ra: float = radius*(0.50 if side%2 == 0 else 0.21)
		var rb: float = radius*(0.21 if side%2 == 0 else 0.50)
		_triangle(surface,center+Vector3.UP*0.039,center+Vector3(cos(b)*rb,0.039,sin(b)*rb),center+Vector3(cos(a)*ra,0.039,sin(a)*ra),Color("658b79"))

static func _coil_point(t: float) -> Vector3:
	var angle: float = t*TAU*2.35
	var radius: float = 0.02+t*0.50
	return Vector3(cos(angle)*radius,0.65-t*0.52,sin(angle)*radius)

static func _coil_ring(t: float, angle: float) -> Vector3:
	var direction: Vector3 = (_coil_point(minf(1.0,t+0.005))-_coil_point(maxf(0.0,t-0.005))).normalized()
	var side: Vector3 = direction.cross(Vector3.UP).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	var radius: float = 0.016+pow(t,1.3)*0.14
	return _coil_point(t)+(side*cos(angle)+up*sin(angle))*radius

static func _conch(surface: SurfaceTool) -> void:
	for ring in range(54):
		var t0: float = float(ring)/54.0
		var t1: float = float(ring+1)/54.0
		for side in range(8):
			var a: float = float(side)*TAU/8.0
			var b: float = float(side+1)*TAU/8.0
			var color := Color("d3bc9d") if ring%6 < 4 else Color("b79583")
			_triangle(surface,_coil_ring(t0,a),_coil_ring(t1,a),_coil_ring(t0,b),color)
			_triangle(surface,_coil_ring(t0,b),_coil_ring(t1,a),_coil_ring(t1,b),color)
	var direction: Vector3 = (_coil_point(1.0)-_coil_point(0.99)).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	var up: Vector3 = direction.cross(right).normalized()
	var mouth: Vector3 = _coil_point(1.0)+direction*0.035
	for side in range(12):
		var a: float = float(side)*TAU/12.0
		var b: float = float(side+1)*TAU/12.0
		var ra: Vector3 = right*cos(a)+up*sin(a)
		var rb: Vector3 = right*cos(b)+up*sin(b)
		_triangle(surface,mouth+ra*0.20,mouth+ra*0.14,mouth+rb*0.20,Color("ead3b8"))
		_triangle(surface,mouth+rb*0.20,mouth+ra*0.14,mouth+rb*0.14,Color("ead3b8"))
		_triangle(surface,mouth+ra*0.14,mouth-direction*0.13,mouth+rb*0.14,Color("946b60"))

static func _chest_base(surface: SurfaceTool) -> void:
	var wood := Color("8e7657")
	_box(surface,Vector3(0,0.10,0),Vector3(1.5,0.18,1.0),wood)
	for side: float in [-1.0,1.0]:
		_box(surface,Vector3(side*0.70,0.43,0),Vector3(0.14,0.64,1.0),wood)
		_box(surface,Vector3(0,0.43,side*0.45),Vector3(1.4,0.64,0.12),wood)
		for y: float in [0.20,0.68]:
			_box(surface,Vector3(0,y,side*0.52),Vector3(1.53,0.075,0.035),Color("b7a273"))
	for x: float in [-0.48,0.48]:
		_box(surface,Vector3(x,0.43,-0.525),Vector3(0.10,0.64,0.04),Color("b7a273"))
	_box(surface,Vector3(0,0.62,-0.54),Vector3(0.18,0.20,0.05),Color("c4af7b"))

static func _chest_lid(surface: SurfaceTool) -> void:
	_box(surface,Vector3(0,0.06,-0.52),Vector3(1.58,0.20,1.08),Color("a08a66"))
	for x: float in [-0.48,0.48]:
		_box(surface,Vector3(x,0.17,-0.52),Vector3(0.11,0.045,1.1),Color("c0ac79"))
	for z: float in [-1.04,0.0]:
		_box(surface,Vector3(0,0.12,z),Vector3(1.62,0.10,0.06),Color("baa372"))

static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var p := PackedVector3Array()
	for offset: Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:
		p.append(center+offset*size*0.5)
	for f: Array in [[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]]:
		_triangle(surface,p[f[0]],p[f[2]],p[f[1]],color)
		_triangle(surface,p[f[0]],p[f[3]],p[f[2]],color)

static func _tube(surface: SurfaceTool, start: Vector3, finish: Vector3, radius: float, color: Color) -> void:
	var direction: Vector3 = (finish-start).normalized()
	var side: Vector3 = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.FORWARD).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	for index in range(6):
		var a: float = float(index)*TAU/6.0
		var b: float = float(index+1)*TAU/6.0
		var p: Vector3 = (side*cos(a)+up*sin(a))*radius
		var q: Vector3 = (side*cos(b)+up*sin(b))*radius
		_triangle(surface,start+p,finish+p,start+q,color)
		_triangle(surface,start+q,finish+p,finish+q,color)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a,b,c]:
		surface.set_color(color)
		surface.add_vertex(vertex)
