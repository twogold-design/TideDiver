extends RefCounted
## Barracuda hold a straight hunting lane instead of chasing an orbiting point.
const Ocean = preload("res://scripts/ocean_config.gd")
const TURN_RATE := 0.95
const ARRIVAL_DISTANCE := 4.5
const BODY_HALF_LENGTH := 2.2
const BODY_RADIUS := 0.60
static var _probe: SphereShape3D

static func steer(game: Node, item: Dictionary, delta: float) -> Dictionary:
	_prepare_lane(game, item)
	var lane: Array = item.barracuda_route
	var point: Vector3 = item.node.position
	var start: Vector3 = lane[0]
	var end: Vector3 = lane[1]
	if start.distance_squared_to(end) < 1.0:
		return {"direction":item.direction,"speed_scale":0.0}
	var target_index: int = item.barracuda_target
	var destination: Vector3 = lane[target_index]
	if point.distance_to(destination) < ARRIVAL_DISTANCE:
		item.barracuda_target = 1 - target_index
		destination = lane[item.barracuda_target]
	# Recover from a charge by joining the closest part of the same lane, without
	# swimming indefinitely along the last attack heading or cutting across a hull.
	var line := end - start
	var along := clampf((point-start).dot(line)/line.length_squared(),0.0,1.0)
	var join := start + line * along
	if point.distance_to(join) > 7.0:
		destination = join
	item.barracuda_avoid_time = maxf(0.0,float(item.barracuda_avoid_time)-delta)
	if item.barracuda_avoid_time > 0.0 and point.distance_to(item.barracuda_avoid_point) > 2.5:
		destination = item.barracuda_avoid_point
	var desired := (destination-point).normalized()
	var ahead := point + desired * 5.0
	if item.get("barracuda_blocked",false) or not corridor_clear(game,point,ahead,BODY_RADIUS):
		if item.barracuda_avoid_time <= 0.0 or item.get("barracuda_blocked",false):
			var detour := _detour(game,point,desired,destination)
			item.barracuda_avoid_point = detour
			item.barracuda_avoid_time = 2.5
			desired = (detour-point).normalized()
		else:
			desired = (item.barracuda_avoid_point-point).normalized()
		item.barracuda_blocked = false
	if desired.length_squared() < 0.01:
		return {"direction":item.direction,"speed_scale":0.0}
	var direction: Vector3 = item.direction
	var yaw := atan2(direction.x,-direction.z)
	var target_yaw := atan2(desired.x,-desired.z)
	var turn := wrapf(target_yaw-yaw,-PI,PI)
	# At exactly 180 degrees a vector lerp collapses or flips. An angular step
	# remains finite and keeps one turn direction throughout the entire U-turn.
	if absf(absf(turn)-PI) < 0.01:
		turn = PI * float(item.barracuda_turn_side)
	yaw += clampf(turn,-TURN_RATE*delta,TURN_RATE*delta)
	var pitch := move_toward(asin(clampf(direction.y,-1.0,1.0)),asin(clampf(desired.y,-0.65,0.65)),0.65*delta)
	var next_direction := Vector3(sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var alignment := maxf(0.0,next_direction.dot(desired))
	return {"direction":next_direction,"speed_scale":0.16+0.84*alignment*alignment}

static func _prepare_lane(game: Node, item: Dictionary) -> void:
	if item.has("barracuda_route") and item.barracuda_route_home == item.home:
		return
	var lane: Array = item.get("barracuda_lane",[])
	if lane.size() != 2:
		lane = _find_lane(game,item)
	item.barracuda_route = lane.duplicate()
	item.barracuda_route_home = item.home
	var axis: Vector3 = lane[1]-lane[0]
	item.barracuda_target = 1 if axis.dot(item.direction) >= 0.0 else 0
	item.barracuda_turn_side = 1.0 if sin(float(item.phase)) >= 0.0 else -1.0
	item.barracuda_avoid_time = 0.0
	item.barracuda_avoid_point = item.node.position

static func _find_lane(game: Node, item: Dictionary) -> Array:
	var home: Vector3 = item.home
	# Prefer a long through-route, then shorten it only in confined habitats.
	for half_length: float in [30.0,22.0,14.0]:
		for candidate in range(8):
			var angle := float(item.phase) + float(candidate)*PI/8.0
			var axis := Vector3(sin(angle),0,cos(angle))
			var a := home-axis*half_length
			var b := home+axis*half_length
			a.y = maxf(home.y,Ocean.seabed_height(a.x,a.z)+4.0)
			b.y = maxf(home.y,Ocean.seabed_height(b.x,b.z)+4.0)
			if absf(a.y-home.y) > 8.0 or absf(b.y-home.y) > 8.0:
				continue
			if corridor_clear(game,a,b,1.6) and corridor_clear(game,home,a,1.2) and corridor_clear(game,home,b,1.2):
				return [a,b]
	# At a narrow doorway use an open one-sided route, never a tiny circular orbit.
	for candidate in range(16):
		var axis := Vector3.FORWARD.rotated(Vector3.UP,float(candidate)*TAU/16.0)
		var end := home+axis*20.0
		if corridor_clear(game,home,end,1.2):
			return [home,end]
	return [home,home]

static func _detour(game: Node, point: Vector3, heading: Vector3, destination: Vector3) -> Vector3:
	var best := point
	var best_score := INF
	for angle: float in [-0.6,0.6,-1.2,1.2,-1.9,1.9,PI]:
		var candidate := point+heading.rotated(Vector3.UP,angle)*9.0
		candidate.y = maxf(candidate.y,Ocean.seabed_height(candidate.x,candidate.z)+4.0)
		if corridor_clear(game,point,candidate,1.0):
			var score := candidate.distance_to(destination)+absf(angle)*1.5
			if score < best_score:
				best_score = score
				best = candidate
	return best

static func movement_clear(game: Node, from: Vector3, to: Vector3, direction: Vector3) -> bool:
	return corridor_clear(game,from-direction*BODY_HALF_LENGTH,to+direction*BODY_HALF_LENGTH,BODY_RADIUS)

static func blocked(item: Dictionary) -> void:
	# Do not spin the heading on a rejected movement. Replan a stable detour and
	# turn towards it with the same bounded angular speed on the following frame.
	item.barracuda_avoid_time = 0.0
	item.barracuda_blocked = true

static func corridor_clear(game: Node, from: Vector3, to: Vector3, radius: float) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1,ceili(distance/3.0))
	for index in range(steps+1):
		var point := from.lerp(to,float(index)/steps)
		if point.x < Ocean.X_MIN+4 or point.x > Ocean.X_MAX-4 or point.z < Ocean.Z_MIN+4 or point.z > Ocean.Z_MAX-4 or point.y > -4.0:
			return false
		if point.y < Ocean.seabed_height(point.x,point.z)+radius+0.5:
			return false
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var sideways := (to-from).cross(Vector3.UP).normalized()*radius
	for offset: Vector3 in [Vector3.ZERO,sideways,-sideways,Vector3.UP*radius,Vector3.DOWN*radius]:
		var ray := PhysicsRayQueryParameters3D.create(from+offset,to+offset,1,[game.player.get_rid()])
		if not space.intersect_ray(ray).is_empty():
			return false
	if _probe == null:
		_probe = SphereShape3D.new()
	_probe.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	for point: Vector3 in [from,to]:
		query.transform = Transform3D(Basis.IDENTITY,point)
		if not space.intersect_shape(query,1).is_empty():
			return false
	return true
