extends RefCounted
## Visible ballistic hook with swept collision against scenery and moving fish bodies.
const SPEED := 24.0
const GRAVITY := Vector3(0,-0.8,0)
const BODIES := [Vector3(0.30,0.42,0.70),Vector3(0.34,0.42,0.95),Vector3(0.46,0.52,0.75),Vector3(0.16,0.20,0.65),Vector3(0.55,0.55,0.60),Vector3(0.34,0.42,0.70),Vector3(0.46,0.55,1.5),Vector3(0.30,0.32,1.85),Vector3(0.55,0.52,2.1),Vector3(0.5,0.25,0.85)]

static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.3
	return mat

static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = a.distance_to(b)
	shape.radial_segments = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = (a+b)*0.5
	mesh.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	parent.add_child(mesh)

static func launch(game: Node, start: Vector3, direction: Vector3) -> Dictionary:
	var node := Node3D.new()
	node.name = "FlyingHook"
	var steel := material(Color("c8e5df"))
	rod(node,Vector3(0,0,0.65),Vector3(0,0,-0.15),0.035,steel)
	# A pointed shaft with a visible hooked barb.
	rod(node,Vector3(0,0,-0.15),Vector3(0.14,0,-0.27),0.025,steel)
	rod(node,Vector3(0.14,0,-0.27),Vector3(0.20,0,-0.12),0.022,steel)
	rod(node,Vector3(0.20,0,-0.12),Vector3(0.12,0,-0.05),0.018,steel)
	rod(node,Vector3(-0.13,0,0.65),Vector3(0.13,0,0.65),0.045,material(Color("dd9b50")))
	game.add_child(node)
	node.position = start
	node.look_at(start+direction,Vector3.UP)
	var trail := MeshInstance3D.new()
	trail.mesh = ImmediateMesh.new()
	var mat := material(Color("94dcd6"))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = mat
	game.add_child(trail)
	return {"node":node,"trail":trail,"points":[start],"velocity":direction*SPEED,"distance":start.distance_to(game.player.position),"damage":game.progress.spear_damage()}

static func fraction(a: Vector3, b: Vector3) -> float:
	# First segment intersection with a unit sphere, including starting inside it.
	var c: float = a.length_squared()-1.0
	if c <= 0:
		return 0.0
	var direction := b-a
	var aa: float = direction.length_squared()
	if aa < 0.0000001:
		return INF
	var bb: float = a.dot(direction)
	var discriminant: float = bb*bb-aa*c
	if discriminant < 0:
		return INF
	var t: float = (-bb-sqrt(discriminant))/aa
	return t if t >= 0 and t <= 1 else INF

static func step(game: Node, shot: Dictionary, delta: float) -> bool:
	var start: Vector3 = shot.node.position
	var motion: Vector3 = shot.velocity*delta+GRAVITY*delta*delta*0.5
	var left: float = maxf(0,game.SPEAR_RANGE-float(shot.distance))
	if motion.length() > left:
		motion = motion.normalized()*left
	var end: Vector3 = start+motion
	var nearest: float = INF
	var victim: Dictionary = {}
	var wall: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,1,[game.player.get_rid()]))
	if not wall.is_empty():
		nearest = start.distance_to(wall.position)/maxf(motion.length(),0.0001)
	for item in game.fish:
		if not item.alive:
			continue
		var inverse: Basis = item.node.global_basis.inverse()
		var default_center := Vector3(0,0,0.65) if int(item.kind) == 7 else Vector3.ZERO
		var center: Vector3 = item.node.get_meta("harpoon_center",default_center)
		var size: Vector3 = BODIES[item.kind]+Vector3.ONE*0.035
		var previous: Vector3 = item.get("previous_position",item.node.position)
		var a: Vector3 = (inverse*(start-previous)-center)/size
		var b: Vector3 = (inverse*(end-item.node.position)-center)/size
		var hit: float = fraction(a,b)
		if hit < nearest:
			nearest = hit
			victim = item
	if nearest != INF:
		impact(game,start.lerp(end,nearest),not victim.is_empty())
		if not victim.is_empty():
			game._hit_fish(victim,int(shot.damage))
		return true
	shot.node.position = end
	shot.velocity += GRAVITY*delta
	shot.distance += motion.length()
	shot.node.look_at(end+(shot.velocity as Vector3).normalized(),Vector3.UP)
	shot.points.append(end)
	if shot.points.size() > 12:
		shot.points.pop_front()
	var line: ImmediateMesh = shot.trail.mesh
	line.clear_surfaces()
	line.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var right: Vector3 = game.camera.global_basis.x*0.035
	for index in range(1,shot.points.size()):
		var a: Vector3 = shot.points[index-1]
		var b: Vector3 = shot.points[index]
		var width_a: Vector3 = right*float(index-1)/shot.points.size()
		var width_b: Vector3 = right*float(index)/shot.points.size()
		for point: Vector3 in [a-width_a,a+width_a,b+width_b,a-width_a,b+width_b,b-width_b]:
			line.surface_add_vertex(point)
	line.surface_end()
	return float(shot.distance) >= game.SPEAR_RANGE-0.001

static func impact(game: Node, point: Vector3, caught: bool) -> void:
	var burst := Node3D.new()
	game.add_child(burst)
	burst.position = point
	var mat := material(Color("efcf89") if caught else Color("c0ebe4"))
	for i in range(6):
		var angle: float = i*TAU/6
		var d := Vector3(cos(angle),sin(angle),0)
		rod(burst,d*0.12,d*0.35,0.018,mat)
	game.effects.append({"node":burst,"life":0.22})

static func dispose(shot: Dictionary) -> void:
	shot.node.queue_free()
	shot.trail.queue_free()
