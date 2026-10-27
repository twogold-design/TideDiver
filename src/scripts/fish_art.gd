extends RefCounted
## Original low-poly fish, facing local -Z. Tail and eel joints animate in FishBrain.
const StonefishArt = preload("res://scripts/stonefish_art.gd")

static func _material(color: String, glow: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = 0.65
	if glow > 0:
		result.emission_enabled = true
		result.emission = Color(color)
		result.emission_energy_multiplier = glow
	return result

static func _ellipsoid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, label: String = "") -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = 10
	shape.rings = 5
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = pos
	mesh.scale = size
	if not label.is_empty():
		mesh.name = label
	parent.add_child(mesh)
	return mesh

static func _fin(parent: Node3D, a: Vector3, b: Vector3, c: Vector3, mat: Material, label: String = "Fin") -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two-sided fins retain their silhouette from either side without shared material changes.
	for vertex: Vector3 in [a,b,c,c,b,a]:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = surface.commit()
	mesh.material_override = mat
	parent.add_child(mesh)

static func _spine(parent: Node3D, start: Vector3, end: Vector3, width: float, mat: Material) -> void:
	var shape := CylinderMesh.new()
	shape.bottom_radius = width
	shape.top_radius = 0.005
	shape.height = start.distance_to(end)
	shape.radial_segments = 5
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = (start+end)*0.5
	mesh.quaternion = Quaternion(Vector3.UP,(end-start).normalized())
	parent.add_child(mesh)

static func _eyes(root: Node3D, width: float, height: float, z: float, big: bool = false) -> void:
	var white := _material("eee6bb")
	var pupil := _material("0b202b")
	for side: float in [-1.0,1.0]:
		var radius: float = 0.12 if big else 0.075
		_ellipsoid(root,Vector3(side*width,height,z),Vector3.ONE*radius,white,"Eye")
		_ellipsoid(root,Vector3(side*(width+radius*0.55),height,z-0.02),Vector3(radius*0.6,radius*0.7,radius*0.7),pupil)

static func _tail(root: Node3D, z: float, span: float, length: float, mat: Material) -> Node3D:
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position.z = z
	root.add_child(tail)
	_ellipsoid(tail,Vector3(0,0,0.08),Vector3(0.09,0.11,0.2),mat)
	for side: float in [-1.0,1.0]:
		_fin(tail,Vector3(0,0,0),Vector3(0,side*span,length),Vector3(0,side*0.10,length*0.55),mat)
	return tail

static func build(kind: int) -> Node3D:
	if kind == 9:
		return StonefishArt.build()
	var root := Node3D.new()
	root.name = "FishArt"
	if kind == 7:
		_build_moray(root)
		return root
	var colors: Array[String] = ["e99a42","3c9ba8","65488d","a9d5dc","a8a566","c96043","286ba2","7d9170","688b9d"]
	var widths: Array[float] = [0.28,0.32,0.42,0.13,0.52,0.29,0.43,0.25,0.53]
	var heights: Array[float] = [0.40,0.39,0.47,0.17,0.52,0.38,0.52,0.25,0.48]
	var lengths: Array[float] = [0.65,0.92,0.70,0.60,0.55,0.65,1.45,1.5,1.85]
	var w: float = widths[kind]
	var h: float = heights[kind]
	var length: float = lengths[kind]
	var body := _material(colors[kind])
	var pale := _material("e0e9d2")
	var fin := _material("efbd50" if kind in [0,6] else colors[kind])
	_ellipsoid(root,Vector3.ZERO,Vector3(w,h,length),body,"Body")
	_ellipsoid(root,Vector3(0,-h*0.43,-length*0.08),Vector3(w*0.89,h*0.58,length*0.88),pale,"Belly")
	_eyes(root,w*0.82,h*0.23,-length*0.62,kind in [2,4])
	_tail(root,length*0.82,h*(1.5 if kind in [3,6,8] else 1.0),length*0.56,fin)
	for side: float in [-1.0,1.0]:
		var wing: float = 1.05 if kind == 8 else (0.7 if kind == 6 else 0.42)
		_fin(root,Vector3(side*w,-0.04,-length*0.3),Vector3(side*(w+wing),-0.2,length*0.4),Vector3(side*w,-0.08,length*0.35),fin,"PectoralFin")
	if kind != 4:
		_fin(root,Vector3(0,h*0.8,-length*0.3),Vector3(0,h+(0.7 if kind == 8 else 0.28),length*0.02),Vector3(0,h*0.7,length*0.6),fin,"DorsalFin")
	match kind:
		0:
			for z: float in [-0.24,0.12,0.37]:
				_ellipsoid(root,Vector3(0,0,z),Vector3(w*1.02,h*0.96,0.045),_material("9d5534"),"Band")
		1,3:
			for side: float in [-1.0,1.0]:
				_ellipsoid(root,Vector3(side*w*0.95,0,0),Vector3(0.025,0.045,length*0.8),_material("d3e8c7"),"SilverStripe")
		2:
			var light := _material("a5ffe2",1.6)
			_spine(root,Vector3(0,0.3,-0.35),Vector3(0,0.93,-0.55),0.035,body)
			_spine(root,Vector3(0,0.93,-0.55),Vector3(0,0.80,-0.88),0.025,body)
			_ellipsoid(root,Vector3(0,0.78,-0.88),Vector3.ONE*0.13,light,"Lure")
			for side: float in [-1.0,1.0]:
				for i in range(4):
					_ellipsoid(root,Vector3(side*w*0.88,-0.13,-0.3+i*0.18),Vector3.ONE*0.045,light,"LightOrgan")
		4:
			for i in range(18):
				var y: float = 1.0-2.0*(float(i)+0.5)/18.0
				var radius: float = sqrt(1-y*y)
				var normal := Vector3(cos(i*2.399)*radius,y,sin(i*2.399)*radius)
				_ellipsoid(root,normal*0.51,Vector3.ONE*0.055,_material("4d6651"),"Spot")
				_spine(root,normal*0.49,normal*0.69,0.035,pale)
		5:
			var ivory := _material("f4dbb0")
			for i in range(6):
				var z: float = -0.42+float(i)*0.17
				_ellipsoid(root,Vector3(0,0,z),Vector3(w*1.02,h*0.96,0.035),ivory,"Stripe")
				_spine(root,Vector3(0,0.18,z),Vector3(0,0.95+0.18*sin(i),z+0.18),0.04,ivory)
				for side: float in [-1.0,1.0]:
					var tip := Vector3(side*(0.95+0.15*sin(i)),0.30-float(i)*0.12,z+0.28)
					_fin(root,Vector3(side*w,-0.05,z-0.05),tip,Vector3(side*w,-0.1,z+0.18),fin,"FanFin")
					_spine(root,Vector3(side*w,-0.05,z),tip,0.023,ivory)
		6:
			for i in range(4):
				var z: float = 0.5+i*0.19
				_fin(root,Vector3(0,h*0.55,z),Vector3(0,h*0.75,z+0.08),Vector3(0,h*0.4,z+0.16),fin,"Finlet")
		8:
			_ellipsoid(root,Vector3(0,-0.04,-1.37),Vector3(0.37,0.22,0.62),body,"Snout")
			_ellipsoid(root,Vector3(0,-0.22,-1.45),Vector3(0.30,0.025,0.30),_material("233d4a"),"Mouth")
			for side: float in [-1.0,1.0]:
				for i in range(3):
					_ellipsoid(root,Vector3(side*0.50,0,-0.55+i*0.13),Vector3(0.022,0.23,0.025),_material("314d60"),"Gill")
	return root

static func _build_moray(root: Node3D) -> void:
	var skin := _material("657b52")
	var spot := _material("b6be83")
	_ellipsoid(root,Vector3(0,0,-0.65),Vector3(0.29,0.30,0.64),skin,"Head")
	_ellipsoid(root,Vector3(0,-0.16,-0.98),Vector3(0.22,0.025,0.30),_material("223629"),"Mouth")
	_eyes(root,0.25,0.10,-0.94)
	var parent: Node3D = root
	for i in range(6):
		var joint := Node3D.new()
		joint.name = "Tail" if i == 0 else "Segment%d" % i
		joint.position.z = 0.0 if i == 0 else 0.42
		parent.add_child(joint)
		var width: float = 0.26-float(i)*0.032
		_ellipsoid(joint,Vector3(0,0,0.17),Vector3(width,width,0.4),skin)
		_fin(joint,Vector3(0,width,0),Vector3(0,width+0.18,0.24),Vector3(0,width,0.45),spot,"RibbonFin")
		for side: float in [-1.0,1.0]:
			_ellipsoid(joint,Vector3(side*width*0.95,0.04,0.20),Vector3(0.025,0.06,0.09),spot,"Mottle")
		parent = joint
