extends RefCounted
## Local reactive fish simulation. Only the game physics clock advances behaviour.
const FishData = preload("res://scripts/fish_catalog.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const SWIM_CADENCE := [4.7,5.8,3.5,10.0,3.4,3.0,7.6,5.0,4.4]

static func prepare(item: Dictionary) -> void:
	if item.has("state"):
		return
	item.state = "camouflaged" if FishData.SPECIES[item.kind].behavior == "camouflage" else "patrol"
	item.timer = 0.0
	item.direction = Vector3.FORWARD.rotated(Vector3.UP,float(item.phase))
	item.attack_cooldown = 0.0
	item.alerted = false
	item.armor = false

static func alarm(game: Node, source: Dictionary) -> void:
	prepare(source)
	for other in game.fish:
		if not other.alive or other.node.position.distance_to(source.node.position) > 18.0:
			continue
		if other != source and not _clear(game,source.node.position,other.node.position):
			continue
		prepare(other)
		var behavior: String = FishData.SPECIES[other.kind].behavior
		if behavior == "camouflage":
			other.state = "exposed"
			other.timer = 3.0
		elif behavior in ["predator","ambush"]:
			other.alerted = true
		elif behavior == "armored" and other.state != "recover":
			other.state = "inflate"
			other.timer = 4.0
			other.armor = true
		else:
			other.state = "flee"
			other.timer = 4.0
			other.direction = _away(other.node.position,game.player.position)

static func _away(point: Vector3, threat: Vector3) -> Vector3:
	var away: Vector3 = point-threat
	away.y *= 0.35
	return away.normalized() if away.length_squared() > 0.01 else Vector3.RIGHT

static func advance(game: Node, item: Dictionary, delta: float) -> void:
	prepare(item)
	if delta <= 0 or not item.alive:
		return
	var node: Node3D = item.node
	var data: Dictionary = FishData.SPECIES[item.kind]
	var previous_direction: Vector3 = item.direction
	var distance: float = node.position.distance_to(game.player.position)
	# Far-away animals keep their habitat without spending collision-query time.
	node.visible = distance < 190.0 if game.state == "dive" else true
	if game.state == "dive" and distance > 140.0:
		return
	item.timer = maxf(0,float(item.timer)-delta)
	item.attack_cooldown = maxf(0,float(item.attack_cooldown)-delta)
	if data.behavior == "camouflage":
		_advance_stonefish(game,item,delta)
		return
	var alert_range: float = float(data.alert)
	if Input.is_action_pressed("stealth"):
		alert_range *= 0.48
	elif Input.is_action_pressed("boost"):
		alert_range *= 1.65
	if item.alerted:
		alert_range = maxf(alert_range,22.0)
	var detects: bool = game.state == "dive" and distance < alert_range and _clear(game,node.position,game.player.position)
	var behavior: String = data.behavior
	if behavior in ["predator","ambush"]:
		if item.state == "patrol" and detects and item.attack_cooldown <= 0:
			item.alerted = false
			item.state = "windup"
			item.timer = 1.15
			item.direction = (game.player.position-node.position).normalized()
			game.hunt_warning = "%s 正在蓄力！横向游动避开冲刺" % data.name
			game.hunt_warning_timer = 1.5
		elif item.state == "windup" and item.timer <= 0:
			item.state = "charge"
			item.timer = 1.15
		elif item.state == "charge":
			if distance < float(data.radius)+1.0 and _clear(game,node.position,game.player.position):
				game.take_hunt_damage(18.0 if behavior == "predator" else 12.0,false,data.name)
				item.timer = 0.0
			if item.timer <= 0:
				item.state = "recover"
				item.timer = 3.5
				item.attack_cooldown = 5.0
		elif item.state == "recover" and item.timer <= 0:
			item.state = "patrol"
	elif behavior == "armored":
		if item.state == "patrol" and detects:
			item.state = "inflate"
			item.timer = 3.5
			item.armor = true
		elif item.state == "inflate" and item.timer <= 0:
			item.state = "recover"
			item.timer = 4.0
			item.armor = false
		elif item.state == "recover" and item.timer <= 0:
			item.state = "patrol"
	elif detects and item.state == "patrol":
		item.state = "flee"
		item.timer = 3.0 if behavior == "calm" else 4.5
		item.direction = _away(node.position,game.player.position)
	if behavior == "venom" and game.state == "dive" and distance < 2.5 and _clear(game,node.position,game.player.position):
		game.take_hunt_damage(6,true,data.name)
	if item.state == "flee" and item.timer <= 0:
		item.state = "patrol"
	var desired: Vector3 = item.direction
	var speed: float = float(data.speed)
	match str(item.state):
		"flee":
			if detects:
				desired = _away(node.position,game.player.position)
			speed *= 1.65
		"windup":
			speed = 0.1
		"charge":
			speed = 14.0 if behavior == "predator" else 11.0
		"recover":
			speed *= 0.35
		"inflate":
			speed *= 0.2
		_:
			var phase: float = float(item.phase)+game.clock*0.13
			var roam: float = 16.0 if int(item.kind) >= 3 else 7.0
			var destination: Vector3 = item.home+Vector3(sin(phase)*roam,sin(phase*0.7)*3.0,cos(phase)*roam)
			# An island ridge is a boundary to swim around, never a higher patrol floor.
			if Ocean.seabed_height(destination.x,destination.z)+3.0 > -5.0:
				destination = item.home
			desired = (destination-node.position).normalized()
			if behavior == "ambush":
				speed *= 0.25
	if item.state != "charge":
		item.direction = (item.direction as Vector3).lerp(desired,minf(1,delta*3.5)).normalized()
	var motion: Vector3 = (item.direction as Vector3)*speed*delta
	var next: Vector3 = node.position+motion
	next.x = clampf(next.x,Ocean.X_MIN+5,Ocean.X_MAX-5)
	next.z = clampf(next.z,Ocean.Z_MIN+5,Ocean.Z_MAX-5)
	var floor_limit: float = maxf(Ocean.Y_MIN+2,Ocean.seabed_height(next.x,next.z)+3.0)
	var water_column: bool = floor_limit <= -5.0
	if water_column:
		next.y = clampf(next.y,floor_limit,-5.0)
	# Sweep ahead so both fleeing fish and charging predators turn before solid reefs.
	var margin: float = maxf(0.9,float(data.radius))
	var lookahead: Vector3 = next+(item.direction as Vector3)*margin
	if water_column and _wet_path(node.position,lookahead,margin) and _clear(game,node.position,lookahead):
		node.position = next
	else:
		item.direction = (item.direction as Vector3).rotated(Vector3.UP,1.45)
		if item.state == "charge":
			item.state = "recover"
			item.timer = 3.5
	if (item.direction as Vector3).length_squared() > 0.01:
		node.look_at(node.position+(item.direction as Vector3),Vector3.UP)
	var scale_target: float = 1.5 if item.armor else 1.0
	node.scale = node.scale.lerp(Vector3.ONE*scale_target,minf(1,delta*5))
	_animate_pose(item,delta,speed,previous_direction)

static func _wet_path(from: Vector3, to: Vector3, clearance: float) -> bool:
	# Ray casts alone cannot reject a point wholly inside a concave terrain volume.
	# Sample its water column as well, including long charge steps across a ridge.
	var bank_reach: float = Ocean.CANYON_BEND_AMPLITUDE+Ocean.CANYON_BANK_HALF_WIDTH+4.0
	if minf(from.x,to.x) > Ocean.CANYON_CENTER.x+bank_reach or maxf(from.x,to.x) < Ocean.CANYON_CENTER.x-bank_reach or minf(from.z,to.z) > Ocean.CANYON_CENTER.z+Ocean.CANYON_HALF_LENGTH+4.0 or maxf(from.z,to.z) < Ocean.CANYON_CENTER.z-Ocean.CANYON_HALF_LENGTH-4.0:
		return true
	var steps: int = maxi(1,ceili(from.distance_to(to)/2.0))
	for index in range(steps+1):
		var point: Vector3 = from.lerp(to,float(index)/steps)
		if point.y < Ocean.seabed_height(point.x,point.z)+clearance:
			return false
	return true

static func _animate_pose(item: Dictionary, delta: float, speed: float, previous_direction: Vector3) -> void:
	# All deformation is below the hunting root, preserving its position and hit basis.
	var motion: Node3D = item.node.get_node_or_null("Motion")
	if motion == null:
		return
	var kind: int = item.kind
	var state: String = item.state
	var data: Dictionary = FishData.SPECIES[kind]
	var blend: float = 1.0-exp(-delta*7.0)
	var activity: float = lerpf(float(item.get("motion_activity",1.0)),clampf(speed/float(data.speed),0.12,2.2),blend)
	item.motion_activity = activity
	var cadence: float = SWIM_CADENCE[kind]
	var phase: float = float(item.get("motion_phase",item.phase))+delta*cadence*(0.50+0.50*activity)
	# All strokes (.5 and .65 frequencies included) share a twenty-cycle period.
	item.motion_phase = fposmod(phase,20.0*TAU)
	var direction: Vector3 = item.direction
	var turn_rate: float = previous_direction.cross(direction).y/maxf(delta,0.0001)
	var bank: float = lerpf(float(item.get("motion_bank",0.0)),clampf(turn_rate*0.28,-0.32,0.32),blend)
	item.motion_bank = bank
	var windup: float = lerpf(float(item.get("motion_windup",0.0)),1.0 if state == "windup" else 0.0,blend)
	var charge: float = lerpf(float(item.get("motion_charge",0.0)),1.0 if state == "charge" else 0.0,blend)
	var recovering: float = lerpf(float(item.get("motion_recover",0.0)),1.0 if state == "recover" else 0.0,blend)
	item.motion_windup = windup
	item.motion_charge = charge
	item.motion_recover = recovering
	var beat: float = sin(phase)
	var amplitude: float = (0.16+0.13*activity)*(1.0-windup*0.4)
	# A steady head, a slight rolling trunk and a delayed tail avoid a rigid pendulum.
	motion.rotation = Vector3(sin(phase*0.5)*0.018+windup*0.055-charge*0.035,beat*0.018,bank+sin(phase-0.45)*0.025)
	motion.position = Vector3(0,sin(phase*0.5)*0.018,windup*0.10-charge*0.08)
	motion.scale = Vector3(1.0+windup*0.025,1.0,1.0-windup*0.055+charge*0.025)
	var flex: Node3D = motion.get_node("BodyFlex")
	flex.rotation.y = beat*(0.026+activity*0.012)+windup*0.10
	var tail: Node3D = motion.get_node_or_null("Tail") if kind == 7 else flex.get_node_or_null("Tail")
	if tail != null:
		tail.rotation.y = sin(phase-0.85)*amplitude+windup*0.12
		if kind == 7:
			var joint: Node3D = tail
			for index in range(1,6):
				joint = joint.get_node("Segment%d" % index)
				joint.rotation.y = sin(phase-0.85-index*0.68)*(0.15+activity*0.085)+windup*0.12*sin(index*0.65)
	for side: float in [-1.0,1.0]:
		var fin: Node3D = flex.get_node_or_null("PectoralLeft" if side < 0 else "PectoralRight")
		if fin != null:
			fin.rotation.z = side*(sin(phase*0.65+side*0.22)*(0.10+recovering*0.11)*(1.0-charge*0.65)+windup*0.20+recovering*0.10)
			fin.rotation.y = side*(charge*0.48-windup*0.18)
	var jaw: Node3D = motion.get_node_or_null("Jaw")
	if jaw != null:
		jaw.rotation.x = -(windup*0.16+charge*0.65+recovering*(0.07+0.035*sin(phase*0.5)))

static func _clear(game: Node, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from,to,1,[game.player.get_rid()])
	return game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func _advance_stonefish(game: Node, item: Dictionary, _delta: float) -> void:
	var node: Node3D = item.node
	# A bottom-dweller holds its authored home, including fixtures used by hunting.
	node.position = item.home
	if item.state not in ["camouflaged","exposed"]:
		item.state = "camouflaged"
	if item.state == "exposed" and item.timer <= 0.0:
		item.state = "camouflaged"
	var center: Vector3 = node.get_meta("contact_center",Vector3(0,0.25,0))
	var radii: Vector3 = node.get_meta("contact_radii",Vector3(0.5,0.25,0.85))
	var contact: Vector3 = (node.to_local(game.player.global_position)-center)/(radii+Vector3.ONE*0.65)
	if game.state == "dive" and not game.entry_active and contact.length_squared() <= 1.0 and _clear(game,node.to_global(center),game.player.global_position):
		item.state = "exposed"
		item.timer = 3.0
		if game.hurt_cooldown <= 0.0:
			game.take_hunt_damage(12.0,true,"石头鱼")
	var exposed: float = smoothstep(0.0,0.35,minf(item.timer,0.35)) if item.state == "exposed" else 0.0
	var spines: Node3D = node.get_node_or_null("Spines")
	if spines != null:
		spines.rotation.x = -0.18*exposed
	for side: int in [-1,1]:
		var fin: Node3D = node.get_node_or_null("PectoralLeft" if side < 0 else "PectoralRight")
		if fin != null:
			fin.rotation.z = side*(exposed*0.18+sin(game.clock*1.7+item.phase)*0.008)
	var tail: Node3D = node.get_node_or_null("Tail")
	if tail != null:
		tail.rotation.y = sin(game.clock*4.2+item.phase)*0.09*exposed

