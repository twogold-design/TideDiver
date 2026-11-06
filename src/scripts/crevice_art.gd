extends RefCounted
## Real open rock pockets. The opening faces -Z and never has a solid front cap.
const Geology = preload("res://scripts/ocean_geology.gd")
const MOUTH := Vector3(0,1.25,-1.0)
static var _materials: Dictionary = {}
static var _shells: Dictionary = {}
static var _sphere: SphereMesh
static var _electric_shader: Shader

static func build(variant: int = 0, with_clam: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "LightningClamCave" if with_clam else "MorayRockCrevice"
	root.set_meta("mouth",MOUTH)
	root.set_meta("with_clam",with_clam)
	root.set_meta("opening_forward",Vector3.FORWARD)
	var offset: float = float(posmod(variant,3))*.10
	# Each hull belongs to an individual stone. There is deliberately no enclosing
	# collision box: fish, hooks and the camera can see into the actual cavity.
	_rock(root,"LeftButtress",Vector3(-2.08,1.40,.45),Vector3(2.60,3.40,4.90),variant)
	_rock(root,"RightButtress",Vector3(2.14,1.28,.60),Vector3(2.80,3.16,4.70),variant+2)
	_rock(root,"WeatheredRoof",Vector3(-.08,3.12+offset,.42),Vector3(5.70,1.30,4.56),variant+4)
	_rock(root,"RecessedBack",Vector3(.06,1.42,2.95),Vector3(4.30,3.16,1.25),variant+1)
	# A second offset crown and broken ledges give the silhouette a fractured,
	# naturally settled outline instead of a doorway made from square bricks.
	_rock(root,"SplitCrown",Vector3(-1.15,3.56+offset,.93),Vector3(2.95,.87,2.25),variant+5)
	_rock(root,"LeftLip",Vector3(-1.43,.44,-1.16),Vector3(1.23,1.18,1.75),variant+3)
	_rock(root,"RightLip",Vector3(1.45,.30,-1.12),Vector3(1.30,.91,1.59),variant+6)
	for index in range(4):
		var side: float = -1.0 if index%2 == 0 else 1.0
		var point := Vector3(side*(2.50+float(index/2)*.43),.16,-.90+float(index/2)*1.6)
		_rock(root,"BrokenStone%d" % index,point,Vector3(.73,.53,.94),variant+index+1,false)
	# Sparse encrusting patches and tube mouths soften the exposed roof edges.
	var patches: Array[Transform3D] = []
	for index in range(5):
		var point := Vector3(-1.85+float(index)*.82,3.65+offset,.05+sin(index*2.7)*.33)
		patches.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.33,.055,.23)),point))
	_batch_ellipsoids(root,"AlgalCrust",patches,_mat("7d8f69"))
	var tubes: Array[Transform3D] = []
	var mouths: Array[Transform3D] = []
	for side: float in [-1.0,1.0]:
		for index in range(3):
			var point := Vector3(side*(2.0+index*.19),.91+index*.15,-1.60+index*.10)
			tubes.append(Transform3D(Basis(Vector3.BACK,side*.25).scaled(Vector3(.105,.18,.085)),point))
			mouths.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.065,.022,.050)),point+Vector3(0,.14,-.032)))
	_batch_ellipsoids(root,"EncrustingTubes",tubes,_mat("ba916e"))
	_batch_ellipsoids(root,"TubeMouths",mouths,_mat("394c45"))
	if with_clam:
		_rock(root,"ClamShelf",Vector3(0,.16,.20),Vector3(1.90,.55,1.85),variant+3,false)
		root.add_child(_clam())
	return root

static func _rock(parent: Node3D, label: String, center: Vector3, size: Vector3, variant: int, solid: bool = true) -> void:
	var mesh: ArrayMesh = Geology.rock_mesh(variant)
	var bounds: AABB = mesh.get_aabb()
	var scale: Vector3 = size/bounds.size
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = Geology.rock_material()
	visual.scale = scale
	visual.position = center-bounds.get_center()*scale
	visual.visibility_range_end = 150.0
	visual.visibility_range_end_margin = 12.0
	parent.add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.name = label+"Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(vertices.size()):
			vertices[index] = (vertices[index]-bounds.get_center())*scale
		hull.points = vertices
		collision.shape = hull
		body.position = center
		body.add_child(collision)
		parent.add_child(body)

static func _mat(hex: String) -> StandardMaterial3D:
	if not _materials.has(hex):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(hex)
		material.roughness = .88
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[hex] = material
	return _materials[hex]

static func _ellipsoid(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = _sphere_mesh()
	visual.material_override = material
	visual.position = point
	visual.scale = size
	parent.add_child(visual)
	return visual

static func _sphere_mesh() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 12
		_sphere.rings = 6
	return _sphere

static func _batch_ellipsoids(parent: Node3D, label: String, transforms: Array[Transform3D], material: Material) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _sphere_mesh()
	batch.instance_count = transforms.size()
	for index in range(transforms.size()):
		batch.set_instance_transform(index,transforms[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = batch
	visual.material_override = material
	visual.visibility_range_end = 65.0
	visual.visibility_range_end_margin = 8.0
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)

static func _clam() -> Node3D:
	var root := Node3D.new()
	root.name = "LightningClam"
	root.position = Vector3(0,.65,-.35)
	root.rotation.x = -.20
	root.set_meta("decorative_only",true)
	root.set_meta("species_name","闪电贝")
	for upper: bool in [false,true]:
		var valve := MeshInstance3D.new()
		valve.name = "UpperValve" if upper else "LowerValve"
		valve.mesh = _shell(upper)
		root.add_child(valve)
	var mantle: MeshInstance3D = _ellipsoid(root,Vector3(0,0,-.07),Vector3(.62,.11,.52),_mat("b94328"))
	mantle.name = "RedMantle"
	# The slender orange feeding tentacles extend beyond the open valve rim.
	var tentacles := MeshInstance3D.new()
	tentacles.name = "Tentacles"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(25):
		var angle: float = lerpf(-1.36,1.36,float(index)/24.0)
		var direction := Vector3(sin(angle),.12+sin(index*2.31)*.22,-cos(angle))
		var base := Vector3(sin(angle)*.59,.0,.28-cos(angle)*.68)
		var length: float = .26+.14*(.5+.5*sin(index*1.73))
		var previous: Vector3 = base
		for segment in range(4):
			var t: float = float(segment+1)/4.0
			var point: Vector3 = base+direction*length*t+Vector3(cos(angle),.8,sin(angle))*sin(t*PI)*.045
			_tube(surface,previous,point,.016*(1.0-t*.7),.012*(1.0-t*.8))
			previous = point
	surface.generate_normals()
	tentacles.mesh = surface.commit()
	tentacles.material_override = _mat("e96835")
	root.add_child(tentacles)
	# A travelling reflection is confined to the mantle lip; no flashing cave
	# light or scene-wide bloom. Explicit time keeps it frozen while paused.
	var lip := MeshInstance3D.new()
	lip.name = "ElectricLip"
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(48):
		var a: float = float(index)/48.0
		var b: float = float(index+1)/48.0
		for pair: Vector2 in [Vector2(a,0),Vector2(a,1),Vector2(b,1),Vector2(a,0),Vector2(b,1),Vector2(b,0)]:
			var theta: float = lerpf(-1.28,1.28,pair.x)
			var radius: float = .68+pair.y*.045
			ribbon.set_uv(pair)
			ribbon.add_vertex(Vector3(sin(theta)*radius,.025,.28-cos(theta)*(radius+.13)))
	ribbon.generate_normals()
	lip.mesh = ribbon.commit()
	if _electric_shader == null:
		_electric_shader = Shader.new()
		_electric_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float phase = 0.0;
void fragment() {
	float travel = fract(UV.x * 1.4 - phase * 0.62);
	float pulse = smoothstep(0.05, 0.15, travel) * (1.0 - smoothstep(0.20, 0.38, travel));
	vec3 blue = vec3(0.32, 0.70, 0.88);
	vec3 white = vec3(0.83, 0.98, 1.0);
	ALBEDO = mix(blue, white, pulse);
	EMISSION = mix(blue * 0.30, white * 1.7, pulse);
	ROUGHNESS = 0.30;
}
"""
	var glow := ShaderMaterial.new()
	glow.shader = _electric_shader
	lip.material_override = glow
	root.add_child(lip)
	return root

static func _shell(upper: bool) -> ArrayMesh:
	if _shells.has(upper):
		return _shells[upper]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(9):
		for column in range(32):
			for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var t: float = float(row+corner.x)/9.0
				var angle: float = lerpf(-1.43,1.43,float(column+corner.y)/32.0)
				var ridge: float = sin(angle*19.0)*.014*t
				var y: float = (.10+sin(t*PI)*.18+ridge)*(1.0 if upper else -1.0)
				var color: Color = Color("a0907e").lerp(Color("d6c5b0"),.42+.16*sin(angle*19.0)+.12*sin(t*28.0))
				surface.set_color(color)
				surface.add_vertex(Vector3(sin(angle)*t*.74,y,.45-cos(angle)*t*.99))
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	# Vertex colours give ribs and old growth bands real contrast at close range.
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .93
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material)
	_shells[upper] = mesh
	return mesh

static func _tube(surface: SurfaceTool, from: Vector3, to: Vector3, radius_a: float, radius_b: float) -> void:
	var direction: Vector3 = (to-from).normalized()
	var side: Vector3 = direction.cross(Vector3.UP).normalized()
	if side.length_squared() < .1:
		side = Vector3.RIGHT
	var normal: Vector3 = side.cross(direction).normalized()
	for index in range(5):
		var a: float = index*TAU/5.0
		var b: float = (index+1)*TAU/5.0
		var va: Vector3 = side*cos(a)+normal*sin(a)
		var vb: Vector3 = side*cos(b)+normal*sin(b)
		for vertex: Vector3 in [from+va*radius_a,to+va*radius_b,to+vb*radius_b,from+va*radius_a,to+vb*radius_b,from+vb*radius_a]:
			surface.add_vertex(vertex)

static func animate_clam(root: Node3D, time: float) -> void:
	var clam: Node3D = root.get_node_or_null("LightningClam")
	if clam == null:
		return
	var lip: MeshInstance3D = clam.get_node("ElectricLip")
	(lip.material_override as ShaderMaterial).set_shader_parameter("phase",time)
	var upper: Node3D = clam.get_node("UpperValve")
	upper.rotation.x = -.025-.018*sin(time*.75)
	var tentacles: Node3D = clam.get_node("Tentacles")
	tentacles.rotation.y = sin(time*1.1)*.018
	tentacles.scale.y = 1.0+sin(time*1.7)*.075
