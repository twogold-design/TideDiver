extends Node3D
## A few sand-buried rays live beyond Moonlight Sand Terrace, outside the catch pool.
const Ocean = preload("res://scripts/ocean_config.gd")
const RayArt = preload("res://scripts/ray_art.gd")
const DETECT_RADIUS := 9.0
const RAY_COUNT := 6
const ROAM_RADIUS := 48.0
var rays: Array[Dictionary] = []
var habitat_bounds := AABB()
var elapsed := 0.0
var ignored_bodies: Array[RID] = []
var _probe: SphereShape3D
var _body_probe: BoxShape3D
var _movement_exclusions: Array[RID] = []
static var _dust_mesh: SphereMesh

func _ready() -> void:
	name = "MoonlightSandRays"
	_probe = SphereShape3D.new()
	_probe.radius = 0.85
	_body_probe = BoxShape3D.new()
	_body_probe.size = Vector3(2.94,0.88,4.16)
	# Terrain is handled with exact height sampling; buried animals start inside it.
	for body: Node in get_parent().find_children("TerrainCollision","StaticBody3D",true,false):
		_movement_exclusions.append(body.get_rid())
	var terrace: Vector3 = Ocean.exploration_points(6)[1].position
	var offsets: Array[Vector3] = [Vector3(17,0,-3),Vector3(25,0,5),Vector3(32,0,-8),Vector3(18,0,15),Vector3(34,0,14),Vector3(42,0,2)]
	for index in range(RAY_COUNT):
		var home: Vector3 = terrace + offsets[index]
		home.y = Ocean.seabed_height(home.x,home.z)
		var node: Node3D = RayArt.build()
		node.name = "SandRay%d" % index
		add_child(node)
		var cover := MeshInstance3D.new()
		cover.name = "SandCover%d" % index
		cover.mesh = RayArt.sand_cover_mesh()
		cover.material_override = RayArt.sand_material().duplicate()
		cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cover)
		var dust := _make_dust(index)
		var item: Dictionary = {"node":node,"home":home,"rest":home,"state":"buried","velocity":Vector3.ZERO,"timer":0.0,"phase":float(index)*1.71,"heading":float(index)*2.399,"cover":cover,"dust":dust,"dust_age":3.0,"wing_left":node.get_node("WingLeft"),"wing_right":node.get_node("WingRight"),"tail":node.get_node("Tail")}
		rays.append(item)
		habitat_bounds = AABB(home,Vector3.ZERO) if index == 0 else habitat_bounds.expand(home)
	habitat_bounds = habitat_bounds.grow(ROAM_RADIUS+3.0)
	set_meta("location_name","月光沙台 · 外侧沙地")
	set_meta("decorative_only",true)
	set_meta("world_bounds",habitat_bounds)
	reset()

func reset() -> void:
	elapsed = 0.0
	for item: Dictionary in rays:
		item.state = "buried"
		item.rest = item.home
		item.timer = 0.0
		item.velocity = Vector3.ZERO
		item.dust_age = 3.0
		item.heading = float(rays.find(item))*2.399
		_place_buried(item)
		item.cover.transform = item.node.transform
		_set_cover(item,0.94)
		item.dust.visible = false
		_animate_fins(item,0.0)

func advance(delta: float, viewer: Vector3, active: bool = true, sensitivity: float = 1.0) -> void:
	if not active or delta <= 0.0:
		return
	elapsed += delta
	for item: Dictionary in rays:
		item.timer += delta
		var point: Vector3 = item.node.position
		var distance: float = point.distance_to(viewer)
		match item.state:
			"buried":
				if distance < DETECT_RADIUS*sensitivity and _can_see(point+Vector3.UP*0.28,viewer):
					_start_flee(item,viewer)
			"rising":
				_swim(item,viewer,delta,true)
				_set_cover(item,lerpf(0.94,0.32,smoothstep(0.0,1.1,item.timer)))
				if item.timer >= 1.1:
					item.state = "fleeing"
					item.timer = 0.0
			"fleeing":
				_swim(item,viewer,delta,false)
				if item.timer > 11.0 and distance > 20.0 and _safe_to_settle(point,item.heading):
					item.state = "settling"
					item.timer = 0.0
					item.rest = Vector3(point.x,Ocean.seabed_height(point.x,point.z),point.z)
					item.settle_start = point
					item.cover.position = item.rest
					item.cover.basis = _ground_basis(item.rest,item.heading)
					_set_cover(item,0.0)
			"settling":
				if distance < DETECT_RADIUS*sensitivity and _can_see(point,viewer):
					_start_flee(item,viewer)
				else:
					var weight: float = smoothstep(0.0,2.8,item.timer)
					item.node.position = (item.settle_start as Vector3).lerp(item.rest+Vector3.DOWN*0.025,weight)
					item.node.basis = item.node.basis.slerp(_ground_basis(item.rest,item.heading),minf(delta*2.5,1.0))
					item.velocity = Vector3.ZERO
					_set_cover(item,weight*0.94)
					if item.timer >= 2.8:
						item.state = "buried"
						item.timer = 0.0
						_place_buried(item)
		var strength: float = 0.0 if item.state == "buried" else (0.35 if item.state == "settling" else 1.0)
		_animate_fins(item,strength)
		_update_dust(item,delta)

func _start_flee(item: Dictionary, viewer: Vector3) -> void:
	item.state = "rising"
	item.timer = 0.0
	var away: Vector3 = item.node.position-viewer
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(sin(item.phase),0,cos(item.phase))
	item.velocity = away.normalized()*4.0
	item.dust_age = 0.0
	item.dust.position = item.rest+Vector3.UP*0.12
	item.dust.visible = true

func _swim(item: Dictionary, viewer: Vector3, delta: float, rising: bool) -> void:
	var node: Node3D = item.node
	var away: Vector3 = node.position-viewer
	away.y = 0.0
	var direction: Vector3 = (item.velocity as Vector3).normalized()
	if away.length() < 22.0 and away.length_squared() > 0.01:
		direction = direction.lerp(away.normalized(),minf(delta*1.8,1.0)).normalized()
	var to_home: Vector3 = item.home-node.position
	to_home.y = 0.0
	if to_home.length() > ROAM_RADIUS-16.0:
		var tangent := Vector3(-to_home.z,0,to_home.x).normalized()
		if tangent.dot(direction) < 0:
			tangent = -tangent
		var return_weight: float = smoothstep(ROAM_RADIUS-16.0,ROAM_RADIUS-4.0,to_home.length())
		direction = direction.lerp((tangent+to_home.normalized()*1.5).normalized(),return_weight).normalized()
	var speed: float = 4.4 if rising else (6.0 if away.length() < 18.0 else 3.2)
	var desired: Vector3 = direction*speed
	item.velocity = (item.velocity as Vector3).lerp(desired,minf(delta*3.0,1.0))
	var step: Vector3 = item.velocity*delta
	var next: Vector3 = node.position+step
	var floor_height: float = Ocean.seabed_height(next.x,next.z)
	var clearance: float = lerpf(0.06,2.3,smoothstep(0.0,1.1,item.timer)) if rising else 2.3+sin(elapsed*1.1+item.phase)*0.25
	var ahead: Vector3 = next+direction*3.0
	var ahead_floor: float = Ocean.seabed_height(ahead.x,ahead.z)
	var target_y: float = maxf(floor_height+clearance,ahead_floor+1.0)
	next.y = move_toward(node.position.y,target_y,delta*(3.6 if rising else 4.5))
	next.y = maxf(next.y,floor_height+0.08)
	var heading: float = lerp_angle(item.heading,atan2(-direction.x,-direction.z),minf(delta*3.0,1.0))
	var next_basis: Basis = node.basis.slerp(Basis(Vector3.UP,heading),minf(delta*3.0,1.0))
	if not _body_motion_clear(node.position,next+direction*1.7,next_basis):
		var found := false
		for turn: float in [1.25,-1.25,2.2,-2.2]:
			var side: Vector3 = direction.rotated(Vector3.UP,turn)
			var candidate: Vector3 = node.position+side*delta*speed+Vector3.UP*delta*1.3
			candidate.y = maxf(candidate.y,Ocean.seabed_height(candidate.x,candidate.z)+0.10)
			var side_heading: float = lerp_angle(item.heading,atan2(-side.x,-side.z),minf(delta*3.0,1.0))
			var side_basis: Basis = node.basis.slerp(Basis(Vector3.UP,side_heading),minf(delta*3.0,1.0))
			if _body_motion_clear(node.position,candidate+side*0.5,side_basis):
				next = candidate
				heading = side_heading
				next_basis = side_basis
				item.velocity = side*speed
				found = true
				break
		if not found:
			next = node.position+Vector3.UP*delta*2.5
			next_basis = node.basis
			heading = item.heading
			item.velocity = Vector3.ZERO
	# A pursued animal turns back into its sand habitat before crossing the edge.
	var next_offset := Vector2(next.x-item.home.x,next.z-item.home.z)
	if next_offset.length() > ROAM_RADIUS:
		var inward: Vector3 = to_home.normalized()
		next = node.position+inward*speed*delta
		next.y = maxf(next.y,Ocean.seabed_height(next.x,next.z)+0.15)
		heading = lerp_angle(item.heading,atan2(-inward.x,-inward.z),minf(delta*3.0,1.0))
		next_basis = node.basis.slerp(Basis(Vector3.UP,heading),minf(delta*3.0,1.0))
		item.velocity = inward*speed
	if _body_motion_clear(node.position,next,next_basis):
		node.position = next
		node.basis = next_basis
		item.heading = heading

func _place_buried(item: Dictionary) -> void:
	item.node.position = item.rest+Vector3.DOWN*0.025
	item.node.basis = _ground_basis(item.rest,item.heading)

func _ground_basis(point: Vector3, heading: float) -> Basis:
	var dx: float = Ocean.seabed_height(point.x+0.8,point.z)-Ocean.seabed_height(point.x-0.8,point.z)
	var dz: float = Ocean.seabed_height(point.x,point.z+0.8)-Ocean.seabed_height(point.x,point.z-0.8)
	var up := Vector3(-dx/1.6,1.0,-dz/1.6).normalized()
	var back := Vector3(sin(heading),0,cos(heading))
	var right: Vector3 = up.cross(back).normalized()
	return Basis(right,up,right.cross(up).normalized())

func _can_see(from: Vector3, to: Vector3) -> bool:
	return _clear_swim(from,to)

func _clear_swim(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var query := PhysicsRayQueryParameters3D.create(from,to,1,ignored_bodies)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _body_motion_clear(from: Vector3, to: Vector3, pose: Basis) -> bool:
	var excluded: Array[RID] = _movement_exclusions.duplicate()
	excluded.append_array(ignored_bodies)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body_probe
	var center: Vector3 = pose*Vector3(0,0.06,0.92)
	query.transform = Transform3D(pose,to+center)
	query.collision_mask = 1
	query.exclude = excluded
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():
		return false
	query.transform.origin = from+center
	query.motion = to-from
	var travel: PackedFloat32Array = space.cast_motion(query)
	return travel.size() == 0 or travel[0] >= 0.9999

func _safe_to_settle(point: Vector3, heading: float = 0.0) -> bool:
	var ground := Vector3(point.x,Ocean.seabed_height(point.x,point.z),point.z)
	if _ground_basis(ground,0).y.y < 0.96:
		return false
	if not _body_motion_clear(ground,ground,_ground_basis(ground,heading)):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY,ground+Vector3.UP*1.2)
	query.collision_mask = 1
	query.exclude = ignored_bodies
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _animate_fins(item: Dictionary, strength: float) -> void:
	var flap: float = sin(elapsed*5.2+item.phase)*0.29*strength
	item.wing_left.rotation.z = flap
	item.wing_right.rotation.z = -flap
	item.tail.rotation.y = sin(elapsed*3.1+item.phase)*0.16*strength
	item.tail.rotation.x = -0.08*strength

func _set_cover(item: Dictionary, opacity: float) -> void:
	var material: StandardMaterial3D = item.cover.material_override
	material.albedo_color.a = opacity
	item.cover.visible = opacity > 0.01

func _make_dust(index: int) -> MultiMeshInstance3D:
	if _dust_mesh == null:
		_dust_mesh = SphereMesh.new()
		_dust_mesh.radius = 0.16
		_dust_mesh.height = 0.32
		_dust_mesh.radial_segments = 6
		_dust_mesh.rings = 3
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _dust_mesh
	batch.instance_count = 14
	var dust := MultiMeshInstance3D.new()
	dust.name = "DisturbedSand%d" % index
	dust.multimesh = batch
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.64,0.61,0.48,0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust.material_override = material
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	return dust

func _update_dust(item: Dictionary, delta: float) -> void:
	item.dust_age += delta
	var age: float = item.dust_age
	if age > 2.4:
		item.dust.visible = false
		return
	var material: StandardMaterial3D = item.dust.material_override
	material.albedo_color.a = (1.0-age/2.4)*0.40
	for index in range(14):
		var angle: float = float(index)*2.399+item.phase
		var offset := Vector3(sin(angle)*(0.35+age*0.65),age*(0.35+float(index%3)*0.12),cos(angle)*(0.3+age*0.5))
		var size: float = 0.5+age*0.6
		item.dust.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),offset))
