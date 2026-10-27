extends RefCounted
## Local reactive fish simulation. Only the game physics clock advances behaviour.
const FishData = preload("res://scripts/fish_catalog.gd")
const Ocean = preload("res://scripts/ocean_config.gd")

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
			desired = (destination-node.position).normalized()
			if behavior == "ambush":
				speed *= 0.25
	if item.state != "charge":
		item.direction = (item.direction as Vector3).lerp(desired,minf(1,delta*3.5)).normalized()
	var motion: Vector3 = (item.direction as Vector3)*speed*delta
	var next: Vector3 = node.position+motion
	next.x = clampf(next.x,Ocean.X_MIN+5,Ocean.X_MAX-5)
	next.z = clampf(next.z,Ocean.Z_MIN+5,Ocean.Z_MAX-5)
	next.y = clampf(next.y,maxf(Ocean.Y_MIN+2,Ocean.seabed_height(next.x,next.z)+3),-5)
	# Sweep ahead so both fleeing fish and charging predators turn before solid reefs.
	var margin: float = maxf(0.9,float(data.radius))
	var lookahead: Vector3 = next+(item.direction as Vector3)*margin
	if _clear(game,node.position,lookahead):
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
	var tail: Node3D = node.get_node_or_null("Tail")
	if tail:
		tail.rotation.y = sin(game.clock*(12.0 if item.state in ["flee","charge"] else 5.5)+float(item.phase))*0.32
		if int(item.kind) == 7:
			var joint: Node3D = tail
			for index in range(1,6):
				joint = joint.get_node("Segment%d" % index)
				joint.rotation.y = sin(game.clock*6.0+float(item.phase)-index*0.65)*0.22

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

