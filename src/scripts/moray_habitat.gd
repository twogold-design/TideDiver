extends Node3D
## Anchored, huntable morays share the normal catch inventory, never roam out of dens.
const Ocean = preload("res://scripts/ocean_config.gd")
const FishArt = preload("res://scripts/fish_art.gd")
const CaveArt = preload("res://scripts/crevice_art.gd")
const REST := Vector3(0,1.25,-0.60)
const HEAD := Vector3(0,0,-0.75)
const BITE_DAMAGE := 12.0
var dens: Array[Dictionary] = []
var clam_den: Node3D
var reef_bounds: Array[AABB] = []
var ambient_bounds: Array[AABB] = []

static func create(game: Node) -> Node3D:
	var habitat := new()
	habitat.name = "CreviceHabitats"
	game.ocean_root.add_child(habitat)
	# These visual-only residents are placed before caves and have no physics bodies.
	# Reserve their complete orbit and rotated silhouette, not just their current pose.
	for resident: Dictionary in game.marine_life.organisms:
		var visual: MultiMeshInstance3D = resident.visual
		var bounds: AABB = visual.multimesh.mesh.get_aabb()
		var scale: float = resident.scale
		if resident.kind in ["GreenTurtle","Cuttlefish"]:
			var radius := 0.0
			for corner in range(8):
				var vertex: Vector3 = bounds.get_endpoint(corner)
				radius = maxf(radius,Vector2(vertex.x,vertex.z).length())
			radius = radius*scale+.15+(3.4 if resident.kind == "GreenTurtle" else 1.05)
			var offset := Vector3(-radius,bounds.position.y*scale-.27,-radius)
			habitat.ambient_bounds.append(AABB(resident.home+offset,Vector3(radius*2,bounds.size.y*scale+.54,radius*2)))
		else:
			var pose := Transform3D((resident.basis as Basis).scaled(Vector3.ONE*scale),resident.home)
			habitat.ambient_bounds.append((pose*bounds).grow(.30))
	# Coral is visual-only geometry; physics queries alone cannot protect a view
	# into a den. Cache individual colonies instead of the garden's huge envelope.
	var garden: Node3D = game.ocean_root.get_node("OuterOcean/amber_reef/CoralGarden")
	for visual: MultiMeshInstance3D in garden.get_children():
		var bounds: AABB = visual.multimesh.mesh.get_aabb()
		for index in range(visual.multimesh.instance_count):
			habitat.reef_bounds.append(visual.global_transform*visual.multimesh.get_instance_transform(index)*bounds)
	var slots: Array[int] = [16]
	for index in range(game.fish.size()):
		if int(game.fish[index].kind) == 7:
			slots.append(index)
	# The atoll's original moray slot is occupied by a grounded stonefish.
	slots.append(game.COASTAL_FISH_COUNT+4*game.OUTER_FISH_PER_ZONE+5)
	for slot in slots:
		var site: int = 0 if slot < game.COASTAL_FISH_COUNT else 1+(slot-game.COASTAL_FISH_COUNT)/game.OUTER_FISH_PER_ZONE
		var cave: Node3D = habitat._place_cave(game,site,false,habitat.dens.size())
		if cave != null:
			habitat.dens.append({"node":cave,"slot":slot,"site":site})
	habitat.clam_den = habitat._place_cave(game,3,true,habitat.dens.size())
	return habitat

func populate(game: Node) -> void:
	for den: Dictionary in dens:
		var old: Dictionary = game.fish[den.slot]
		old.node.queue_free()
		var animal: Node3D = FishArt.build(7)
		animal.name = "CreviceMoray%d" % int(den.slot)
		game.ocean_root.add_child(animal)
		animal.global_transform = den.node.global_transform*Transform3D(Basis.IDENTITY,REST)
		# Only the exposed head is a target; the hidden tail cannot be shot through rock.
		animal.set_meta("harpoon_center",HEAD)
		animal.set_meta("harpoon_radii",Vector3(.33,.33,.58))
		var phase: float = game.wildlife_rng.randf_range(0,TAU)
		game.fish[den.slot] = {"node":animal,"kind":7,"home":animal.position,"phase":phase,"hp":4,"alive":true,"previous_position":animal.position,"den":den.node,"state":"shelter","timer":2.0+phase,"attack_cooldown":0.0,"alerted":false,"armor":false,"direction":-animal.basis.z,"den_time":phase,"extension":0.0}

func _place_cave(game: Node, site: int, clam: bool, variant: int) -> Node3D:
	var area: Dictionary = Ocean.exploration_areas()[site]
	var footprint := BoxShape3D.new()
	footprint.size = Vector3(7.5,4.2,8.8)
	for attempt in range(320):
		var angle: float = float(attempt)*2.399963+float(variant)*.61
		var radius: float = 30.0+float(attempt%5)*5.5
		# A finer inner-ring fallback finds flat gaps in the atoll's raised reef.
		if attempt >= 160:
			radius = 18.0+float(attempt%23)*1.5
		var point: Vector3 = area.center+Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if site == 3:
			# Place reef caves on the winding sand corridor between coral banks.
			var along: float = 32.0+float(attempt%9)*3.0 if clam else -42.0+float(attempt%29)*3.0
			point = area.center+Vector3(sin((along+6.0)*.055)*6.0,0,along)
		if site == 1:
			point.z = area.center.z-48.0+float(attempt%17)*6.0
			point.x = Ocean.canyon_center_x(point.z)+(-6.0 if attempt%2 == 0 else 6.0)
		var low := INF
		var high := -INF
		for x: float in [-3.5,0.0,3.5]:
			for z: float in [-4.0,0.0,4.0]:
				var height: float = Ocean.seabed_height(point.x+x,point.z+z)
				low = minf(low,height)
				high = maxf(high,height)
		if high > -7.0 or high-low > 1.8:
			continue
		point.y = high-.12
		var crowded := false
		for pickup: Dictionary in game.pickups:
			if Vector2(point.x-pickup.home.x,point.z-pickup.home.z).length() < 8.0:
				crowded = true
		for den: Dictionary in dens:
			if point.distance_to(den.node.position) < 13.0:
				crowded = true
		for resident: Dictionary in game.fish:
			if int(resident.kind) == 9 and point.distance_to(resident.home) < 5.0:
				crowded = true
		for landing: Dictionary in Ocean.DIVE_SITES:
			if point.distance_to(landing.origin+Vector3(0,-6,25)) < 30.0:
				crowded = true
		if crowded or game.explorable_wreck.contains_point(point,8.0):
			continue
		var inward: Vector3 = area.center-point
		inward.y = 0
		var frame := Basis.looking_at(inward.normalized(),Vector3.UP)
		var cave_bounds := AABB(Vector3(-3.6,-2.5,-2.1),Vector3(7.2,6.8,5.8))
		var cave_inverse := Transform3D(frame,point).affine_inverse()
		for resident_bounds: AABB in ambient_bounds:
			if cave_bounds.intersects(cave_inverse*resident_bounds):
				crowded = true
				break
		if crowded:
			continue
		if site == 3:
			var view_bounds: AABB = Transform3D(frame,point)*AABB(Vector3(-3.6,.35,-6),Vector3(7.2,4,9.8))
			for colony: AABB in reef_bounds:
				if view_bounds.intersects(colony):
					crowded = true
			if crowded:
				continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = footprint
		query.transform = Transform3D(frame,point+Vector3.UP*2.45)
		query.collision_mask = 1
		query.exclude = [game.player.get_rid()]
		if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			continue
		# Preserve a clear approach to the visible opening, not just an empty interior.
		var approach: Vector3 = point+frame*Vector3(0,1.25,-6)
		if approach.y < Ocean.seabed_height(approach.x,approach.z)+.8:
			continue
		var cave: Node3D = CaveArt.build(variant,clam)
		cave.name = "LightningClamCave" if clam else "MorayDen%d" % variant
		cave.set_meta("site",site)
		add_child(cave)
		cave.transform = Transform3D(frame,point)
		# Sink side footings into the actual slope without lowering the open mouth.
		for side: float in [-1.0,1.0]:
			var bottom := 0.0
			for z: float in [-1.4,.5,2.4]:
				var foot: Vector3 = cave.to_global(Vector3(side*2.1,0,z))
				bottom = minf(bottom,Ocean.seabed_height(foot.x,foot.z)-point.y-.35)
			CaveArt._rock(cave,"BuriedFootingLeft" if side < 0 else "BuriedFootingRight",Vector3(side*2.1,(bottom+.55)*.5,.45),Vector3(2.7,.55-bottom,4.7),variant+int(side)+7)
		return cave
	push_error("No clear crevice habitat at dive site %d" % site)
	return null

static func advance(game: Node, item: Dictionary, delta: float) -> void:
	if delta <= 0 or not item.alive or game.state in ["paused","service_paused"]:
		return
	var animal: Node3D = item.node
	var cave: Node3D = item.den
	var distance: float = animal.position.distance_to(game.player.position)
	animal.visible = distance < 160.0
	if distance > 140.0:
		return
	item.den_time += delta
	item.timer = maxf(0,item.timer-delta)
	item.attack_cooldown = maxf(0,item.attack_cooldown-delta)
	var head: Vector3 = animal.to_global(HEAD)
	var relative: Vector3 = cave.to_local(game.player.position)-REST
	var forward: bool = relative.z < -.85 and absf(relative.x) < 1.6 and absf(relative.y) < 1.5
	var active: bool = game.state == "dive" and not game.entry_active
	var clear: bool = active and forward and head.distance_to(game.player.position) < 3.1 and _clear(game,head,game.player.position)
	if clear and item.attack_cooldown <= 0 and item.state in ["shelter","peek"]:
		item.state = "windup"
		item.timer = .45
		item.attack_cooldown = 4.0
	var target_extension := 0.0
	match str(item.state):
		"shelter":
			if item.timer <= 0:
				item.state = "peek"
				item.timer = 2.8
		"peek":
			target_extension = .65
			if item.timer <= 0:
				item.state = "shelter"
				item.timer = 4.0+float(item.phase)*.6
		"windup":
			target_extension = .12
			if item.timer <= 0:
				item.state = "strike" if clear else "retract"
				item.timer = .3 if clear else 1.2
		"strike":
			target_extension = 1.45
			if item.timer <= 0:
				item.state = "retract"
				item.timer = 1.3
		"retract":
			if item.timer <= 0:
				item.state = "shelter"
				item.timer = 3.0
	item.extension = move_toward(float(item.extension),target_extension,delta*(8.5 if item.state == "strike" else .85))
	animal.global_transform = cave.global_transform*Transform3D(Basis.IDENTITY,REST+Vector3(0,0,-float(item.extension)))
	var next_head: Vector3 = animal.to_global(HEAD)
	if active and forward and item.state == "strike":
		var contact: Vector3 = Geometry3D.get_closest_point_to_segment(game.player.position,head,next_head)
		if contact.distance_to(game.player.position) < 1.35 and _clear(game,next_head,game.player.position):
			game.take_hunt_damage(BITE_DAMAGE,false,"岩洞海鳗")
			item.state = "retract"
			item.timer = 1.3
	_pose(item)

static func _pose(item: Dictionary) -> void:
	var motion: Node3D = item.node.get_node("Motion")
	var time: float = item.den_time
	motion.rotation.y = sin(time*1.3)*.025
	var jaw: Node3D = motion.get_node("Jaw")
	jaw.rotation.x = -.12-.055*sin(time*1.7)
	if item.state == "windup":
		jaw.rotation.x = -.5
	elif item.state == "strike":
		jaw.rotation.x = -.75
	var joint: Node3D = motion.get_node("Tail")
	for index in range(6):
		joint.rotation.y = sin(time*1.9-float(index)*.65)*.065
		if index < 5:
			joint = joint.get_node("Segment%d" % (index+1))

static func _clear(game: Node, from: Vector3, to: Vector3) -> bool:
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,[game.player.get_rid()])).is_empty()

func animate(time: float, viewer: Vector3) -> void:
	for den: Dictionary in dens:
		den.node.visible = den.node.position.distance_squared_to(viewer) < 170.0*170.0
	if is_instance_valid(clam_den):
		clam_den.visible = clam_den.position.distance_squared_to(viewer) < 170.0*170.0
		if clam_den.visible:
			CaveArt.animate_clam(clam_den,time)

func observation(game: Node) -> String:
	if is_instance_valid(clam_den):
		var point: Vector3 = clam_den.to_global(Vector3(0,.8,-.6))
		if point.distance_to(game.player.position) < 9.0 and _clear(game,point,game.player.position):
			return "闪电贝 · 观赏生物 · 留意外套膜边缘的蓝白闪带"
	for den: Dictionary in dens:
		var resident: Dictionary = game.fish[den.slot]
		var head: Vector3 = resident.node.to_global(HEAD)
		if resident.alive and head.distance_to(game.player.position) < 7.0 and _clear(game,head,game.player.position):
			return "岩缝中的海鳗 · 可用鱼叉捕获，勿贴近洞口"
	return ""
