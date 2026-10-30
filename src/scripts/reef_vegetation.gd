extends Node3D
## Rooted sea grass and ribbon algae, animated entirely in two GPU batches.
const Ocean = preload("res://scripts/ocean_config.gd")
const Coral = preload("res://scripts/coral_garden.gd")
var sway_material: ShaderMaterial
var roots := PackedVector3Array()
var harvests: Array[Dictionary] = []
var _last_time := -INF
static var _shared_material: ShaderMaterial

static func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = _material()
	return _shared_material

static func animate_shared(time: float) -> void:
	if _shared_material != null:
		_shared_material.set_shader_parameter("plant_clock",time)

static func build(parent: Node3D) -> Node3D:
	var meadow = load("res://scripts/reef_vegetation.gd").new()
	meadow.name = "ReefVegetation"
	parent.add_child(meadow)
	meadow.position = Vector3(-180,0,135)
	meadow._populate()
	meadow._register_plants(meadow)
	meadow._register_plants(parent,meadow)
	return meadow

func _populate() -> void:
	sway_material = _material()
	var random := RandomNumberGenerator.new()
	random.seed = 941883
	var garden: Node3D = get_parent().get_node("OuterOcean/amber_reef/CoralGarden")
	var colonies: PackedVector3Array = garden.get_meta("patch_positions")
	for kind in range(2):
		var poses: Array[Transform3D] = []
		var tints: Array[Color] = []
		var count: int = 170 if kind == 0 else 65
		for attempt in range(5000):
			if poses.size() == count:
				break
			var z: float = random.randf_range(-43,36)
			var lane: float = sin((z+6)*.055)*6.0
			var side: float = -1.0 if random.randf()<.5 else 1.0
			var x: float = lane+side*random.randf_range(7.0,42.0)
			# Group vegetation into soft beds; keep the sand route and hosts clear.
			if sin(x*.24+z*.15)+cos(z*.29-x*.11)<-.25:
				continue
			var clear := true
			for colony: Vector3 in colonies:
				if Vector2(x-colony.x,z-colony.z).length_squared()<3.2:
					clear = false
					break
			if not clear:
				continue
			var world := Vector3(global_position.x+x,0,global_position.z+z)
			world.y = Ocean.seabed_height(world.x,world.z)
			var size: float = random.randf_range(.65,1.18)
			poses.append(Transform3D(Basis(Vector3.UP,random.randf_range(-PI,PI))*Basis.from_scale(Vector3.ONE*size),world-global_position))
			tints.append(Color("85b695").lerp(Color("bdc494"),random.randf()) if kind == 0 else Color("b8a276").lerp(Color("80a99a"),random.randf()))
			roots.append(world)
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = _plant_mesh(kind)
		batch.instance_count = poses.size()
		for index in range(poses.size()):
			batch.set_instance_transform(index,poses[index])
			batch.set_instance_color(index,tints[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = "SeagrassBeds" if kind == 0 else "RibbonAlgae"
		visual.multimesh = batch
		visual.material_override = sway_material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 115.0
		visual.visibility_range_end_margin = 14.0
		visual.extra_cull_margin = .8
		add_child(visual)
		visual.set_meta("harvestable_plant",true)
	set_meta("decorative_only",false)
	set_meta("instance_count",roots.size())
	set_meta("draw_batches",2)
	animate(0,global_position)

func _register_plants(node: Node, skip: Node = null) -> void:
	if node == skip:
		return
	if node.get_meta("harvestable_plant",false):
		if node is MultiMeshInstance3D:
			for index in range(node.multimesh.instance_count):
				_register_plant(node,node.multimesh.get_instance_transform(index),index)
		elif node is MeshInstance3D:
			_register_plant(node,node.transform,-1)
	for child: Node in node.get_children():
		_register_plants(child,skip)

func _register_plant(visual: GeometryInstance3D, pose: Transform3D, index: int) -> void:
	var batched: bool = index>=0
	var mesh: Mesh = visual.multimesh.mesh if batched else visual.mesh
	var world: Transform3D = visual.global_transform*pose if batched else visual.global_transform
	var bounds: AABB = mesh.get_aabb()
	var probes := PackedVector3Array()
	# Probe the visible leaves as well as the stem, including tall or tilted grass.
	for height: float in [.25,.55,.85]:
		probes.append(world*Vector3(bounds.get_center().x,bounds.position.y+bounds.size.y*height,bounds.get_center().z))
	var plant := {"visual":visual,"index":index,"pose":pose,"position":probes[1],"probes":probes,"active":true}
	if batched:
		plant["batch"] = visual.multimesh
	harvests.append(plant)

func _set_plant_pose(plant: Dictionary, pose: Transform3D) -> void:
	if plant.index>=0:
		plant.batch.set_instance_transform(plant.index,pose)
	else:
		plant.visual.transform = pose

func reset_harvests() -> void:
	for plant: Dictionary in harvests:
		plant.active = true
		_set_plant_pose(plant,plant.pose)

func cut(plant: Dictionary) -> bool:
	if not harvests.has(plant) or not plant.active:
		return false
	plant.active = false
	var stump: Transform3D = plant.pose
	stump.basis *= Basis.from_scale(Vector3(1,.14,1))
	_set_plant_pose(plant,stump)
	return true

func target(game: Node) -> Dictionary:
	var origin: Vector3 = game.camera.project_ray_origin(game.get_viewport().get_visible_rect().size*.5)
	var direction: Vector3 = game.camera.project_ray_normal(game.get_viewport().get_visible_rect().size*.5)
	var best: Dictionary = {}
	var best_score := INF
	var forward := Vector3(-sin(game.yaw),0,-cos(game.yaw))
	for plant: Dictionary in harvests:
		if not plant.active or game.player.position.distance_squared_to(plant.position)>64.0:
			continue
		for point: Vector3 in plant.probes:
			var reach: Vector3 = point-game.player.position
			var distance: float = reach.length()
			if distance>3.0:
				continue
			var horizontal := Vector3(reach.x,0,reach.z)
			if horizontal.length()>.8 and horizontal.normalized().dot(forward)<-.15:
				continue
			var offset: Vector3 = point-origin
			var along: float = offset.dot(direction)
			var score: float = distance+(offset-direction*along).length()*.2
			if along<=0 or score>=best_score:
				continue
			var ray := PhysicsRayQueryParameters3D.create(game.player.position,point,1,[game.player.get_rid()])
			if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			var sight := PhysicsRayQueryParameters3D.create(origin,point,1,[game.player.get_rid()])
			if not game.get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
				continue
			best = plant
			best_score = score
	return best

func animate(time: float, viewer: Vector3) -> void:
	visible = Vector2(viewer.x-global_position.x,viewer.z-global_position.z).length()<160.0
	if visible and time != _last_time:
		_last_time = time
		sway_material.set_shader_parameter("plant_clock",time)

static func _plant_mesh(kind: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int = 11 if kind == 0 else 7
	for blade in range(blades):
		var angle: float = float(blade)*2.39996
		var height: float = .85+float(blade%5)*.21 if kind == 0 else 1.4+float(blade%4)*.28
		var lean: float = .35+float(blade%3)*.18 if kind == 0 else .8+float(blade%3)*.22
		var direction := Vector3(sin(angle),0,cos(angle))
		var tangent := Vector3(cos(angle),0,-sin(angle))
		for segment in range(9):
			var a: float = float(segment)/9.0
			var b: float = float(segment+1)/9.0
			var quad: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for t: float in [a,b]:
				var sag: float = .30*pow(t,4.0) if kind == 1 else .08*pow(t,4.0)
				var center: Vector3 = direction*(.10+lean*t*t)+Vector3.UP*height*(t-sag)
				var width: float = (.065 if kind == 0 else .18)*pow(maxf(sin(t*PI),0),.65)
				var curl: float = sin(t*10+angle)*t*.12 if kind == 1 else 0.0
				var edge: Vector3 = tangent*width+Vector3.UP*curl
				quad.append(center-edge)
				quad.append(center+edge)
				var slope: float = 1.0-(1.2 if kind == 1 else .32)*pow(t,3.0)
				var normal: Vector3 = tangent.cross(direction*2.0*lean*t+Vector3.UP*height*slope).normalized()
				normals.append(normal)
				normals.append(normal)
			for index: int in [0,2,1,1,2,3]:
				surface.set_normal(normals[index])
				surface.set_color(Color("78967b").lerp(Color("ccd8ac"),(a if index<2 else b)*.8))
				surface.add_vertex(quad[index])
	return surface.commit()

static func _material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float plant_clock = 0.0;
varying float leaf_height;
void vertex() {
    leaf_height = max(VERTEX.y,0.0);
    float phase = MODEL_MATRIX[3].x*0.17+MODEL_MATRIX[3].z*0.23;
    float slow = sin(plant_clock*0.70+phase)*0.085;
    float flutter = sin(plant_clock*1.18+phase*1.7+VERTEX.y*1.4)*0.025;
    float bend = slow+flutter;
    float h = leaf_height;
    VERTEX.x += h*h*bend;
    VERTEX.z += h*h*sin(plant_clock*0.57+phase+0.8)*0.045;
    NORMAL.y -= 2.0*h*(bend*NORMAL.x+sin(plant_clock*0.57+phase+0.8)*0.045*NORMAL.z);
    NORMAL = normalize(NORMAL);
}
void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    ALBEDO = COLOR.rgb*(0.94+sin(leaf_height*9.0)*0.025);
    ROUGHNESS = 0.94;
    SPECULAR = 0.12;
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result
