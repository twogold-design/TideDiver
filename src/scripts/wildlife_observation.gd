extends RefCounted
## Track one visible animal, not just its species, through three seconds of aiming.
const Catalog = preload("res://scripts/wildlife_catalog.gd")
const DURATION := 3.0
const RANGE := 20.0
var target: Dictionary = {}
var elapsed := 0.0
var scan_left := 0.0

func reset() -> void:
	target = {}
	elapsed = 0.0
	scan_left = 0.0

func advance(game: Node, delta: float) -> void:
	if game.state == "paused" or game.bestiary_open:
		return
	if game.state != "dive" or game.entry_active or game.gm_menu_open:
		reset()
		return
	if delta <= 0:
		return
	scan_left -= delta
	if scan_left <= 0:
		scan_left = .08
		var candidate: Dictionary = find_target(game)
		if candidate.get("key","") != target.get("key",""):
			elapsed = 0.0
		target = candidate
	if target.is_empty() or game.progress.has_discovery(target.id):
		return
	elapsed = minf(DURATION,elapsed+minf(delta,.1))
	if elapsed >= DURATION:
		# A last-frame turn or newly occluding wall must not complete a cached aim.
		var confirmed: Dictionary = find_target(game)
		if confirmed.get("key","") == target.key:
			game.record_species(target.id,"observed")
		else:
			reset()

func find_target(game: Node) -> Dictionary:
	var result: Dictionary = {}
	var center: Vector2 = game.get_viewport().get_visible_rect().size*.5
	var origin: Vector3 = game.camera.project_ray_origin(center)
	var forward: Vector3 = game.camera.project_ray_normal(center)
	for item: Dictionary in game.fish:
		if item.alive and item.node.is_visible_in_tree():
			var point: Vector3 = item.node.to_global(item.node.get_meta("harpoon_center",Vector3.ZERO))
			_consider(game,result,game.FishData.SPECIES[item.kind].id,"fish:%d" % item.node.get_instance_id(),point,origin,forward)
	if game.reef_fish.is_visible_in_tree() and game.player.position.distance_to(game.reef_fish.global_position) < 120.0:
		for fish: Dictionary in game.reef_fish.residents:
			if not fish.visual.is_visible_in_tree():
				continue
			var point: Vector3 = fish.get("observation_point",fish.visual.global_transform*Transform3D(Basis.IDENTITY,fish.home).origin)
			_consider(game,result,"reef_"+fish.kind,"reef:%s:%d" % [fish.kind,fish.index],point,origin,forward)
	for animal: Dictionary in game.marine_life.organisms:
		if animal.visual.is_visible_in_tree():
			var pose: Transform3D = animal.world_transform
			var point: Vector3 = pose*animal.visual.multimesh.mesh.get_aabb().get_center()
			_consider(game,result,"marine_"+animal.kind,"marine:%d:%d" % [animal.visual.get_instance_id(),animal.index],point,origin,forward)
	for ray: Dictionary in game.ray_habitat.rays:
		if ray.node.is_visible_in_tree():
			_consider(game,result,"sand_ray","ray:%d" % ray.node.get_instance_id(),ray.node.to_global(Vector3(0,.12,0)),origin,forward)
	if game.canyon_shark.spawned and game.canyon_shark.is_visible_in_tree():
		_consider(game,result,"thresher_shark","thresher",game.canyon_shark.global_position,origin,forward)
	var cave: Node3D = game.crevice_habitat.clam_den
	if is_instance_valid(cave) and cave.is_visible_in_tree():
		_consider(game,result,"lightning_clam","clam",cave.to_global(Vector3(0,.8,-.6)),origin,forward)
	return result

func _consider(game: Node, best: Dictionary, id: String, key: String, point: Vector3, origin: Vector3, direction: Vector3) -> void:
	if game.player.position.distance_squared_to(point) > RANGE*RANGE:
		return
	var offset: Vector3 = point-origin
	var along: float = offset.dot(direction)
	if along <= 0:
		return
	var width: float = maxf(.38,along*.045)
	var error: float = (offset-direction*along).length()/width
	var score: float = error+along*.002
	if error > 1.0 or score >= float(best.get("score",INF)):
		return
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for start: Vector3 in [origin,game.player.position]:
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(start,point,1,[game.player.get_rid()])).is_empty():
			return
	best.clear()
	best.merge({"id":id,"key":key,"point":point,"score":score})
