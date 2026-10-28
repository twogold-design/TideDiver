extends RefCounted
## Reuse sparse fish slots for bottom-dwellers beside actual authored rock meshes.
const Ocean = preload("res://scripts/ocean_config.gd")
const Art = preload("res://scripts/ocean_art.gd")
const Brain = preload("res://scripts/fish_brain.gd")
const FishData = preload("res://scripts/fish_catalog.gd")
const KIND := 9
const PER_SITE := 2
const BODY_OFFSET := 0.035

static func populate(game: Node) -> int:
	if not game.has_meta("stonefish_candidates"):
		game.set_meta("stonefish_candidates",_build_candidates(game))
	var sites: Array = game.get_meta("stonefish_candidates")
	var placed := 0
	for site in range(Ocean.DIVE_SITES.size()):
		var candidates: Array = sites[site]
		if candidates.is_empty():
			push_error("No safe rock-edge habitat for stonefish at site %d" % site)
			continue
		var start: int = game.wildlife_rng.randi_range(0,candidates.size()-1)
		var selected: Array[Vector3] = []
		for index in range(candidates.size()):
			var candidate: Dictionary = candidates[(start+index)%candidates.size()]
			var point: Vector3 = candidate.position
			if not selected.is_empty() and point.distance_to(selected[0]) < 7.0:
				continue
			var slot: int = [17,20][selected.size()] if site == 0 else game.COASTAL_FISH_COUNT+(site-1)*game.OUTER_FISH_PER_ZONE+[12,15][selected.size()]
			var previous: Dictionary = game.fish[slot]
			previous.node.queue_free()
			var node: Node3D = Art.create_fish(KIND)
			node.name = "StonefishSite%d_%d" % [site,selected.size()]
			game.ocean_root.add_child(node)
			node.position = point
			node.basis = _ground_basis(point,game.wildlife_rng.randf_range(-PI,PI))
			var item: Dictionary = {"node":node,"kind":KIND,"home":point,"phase":previous.phase,"hp":int(FishData.SPECIES[KIND].hp),"alive":true,"previous_position":point,"rock_anchor":candidate.rock_anchor,"rock_bounds":candidate.rock_bounds,"stonefish_site":site}
			Brain.prepare(item)
			game.fish[slot] = item
			selected.append(point)
			placed += 1
			if selected.size() == PER_SITE:
				break
		if selected.size() != PER_SITE:
			push_error("Rock-edge habitat is too crowded at site %d" % site)
	return placed

static func _build_candidates(game: Node) -> Array:
	var rocks: Array[Dictionary] = []
	for visual: Node in game.ocean_root.find_children("*","MeshInstance3D",true,false):
		if visual.get_meta("stonefish_rock",false):
			var bounds: AABB = visual.global_transform*visual.mesh.get_aabb()
			rocks.append({"bounds":bounds,"position":bounds.get_center()})
	var geology: Node = game.ocean_root.get_node("OceanGeology")
	for rock: Dictionary in geology.get_meta("stonefish_rocks",[]):
		rocks.append(rock)
	var result: Array = []
	# Rotationally symmetric clearance covers every randomly chosen fish heading.
	var body := CylinderShape3D.new()
	body.radius = 1.05
	body.height = 0.54
	var areas: Array = Ocean.exploration_areas()
	for site in range(areas.size()):
		var area: Dictionary = areas[site]
		var candidates: Array[Dictionary] = []
		for rock: Dictionary in rocks:
			var bounds: AABB = rock.bounds
			if bounds.size.length() < 1.05:
				continue
			var center: Vector3 = bounds.get_center()
			if Vector2(center.x-area.center.x,center.z-area.center.z).length() > float(area.radius)+3.0:
				continue
			# Clear of the complete rock envelope, with enough room to swim past.
			var edges: Array[Vector3] = [Vector3(bounds.end.x+1.05,0,center.z),Vector3(bounds.position.x-1.05,0,center.z),Vector3(center.x,0,bounds.end.z+1.10),Vector3(center.x,0,bounds.position.z-1.10)]
			for point: Vector3 in edges:
				point.y = Ocean.seabed_height(point.x,point.z)+BODY_OFFSET
				if _safe_home(game,point,body):
					candidates.append({"position":point,"rock_anchor":rock.position,"rock_bounds":bounds})
		result.append(candidates)
	return result

static func _safe_home(game: Node, point: Vector3, body: Shape3D) -> bool:
	# The entire animal, including raised venom spines, stays below the surface.
	if point.y > -2.0:
		return false
	if _ground_basis(point,0).y.y < 0.97:
		return false
	for site: Dictionary in Ocean.DIVE_SITES:
		if point.distance_to(site.origin+Vector3(0,-6,25)) < 33.0:
			return false
	if point.distance_to(game.dive_origin+Vector3(0,-6,25)) < 33.0:
		return false
	for pickup: Dictionary in game.pickups:
		if point.distance_to(pickup.home) < 5.0:
			return false
	# Keep the actual central wreck corridor and its five openings free of hazards.
	if game.explorable_wreck.contains_point(point,3.0):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	var frame: Basis = _ground_basis(point,0)
	query.transform = Transform3D(frame,point+frame*Vector3(0,0.29,0))
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

static func _ground_basis(point: Vector3, heading: float) -> Basis:
	var dx: float = (Ocean.seabed_height(point.x+0.6,point.z)-Ocean.seabed_height(point.x-0.6,point.z))/1.2
	var dz: float = (Ocean.seabed_height(point.x,point.z+0.6)-Ocean.seabed_height(point.x,point.z-0.6))/1.2
	var normal := Vector3(-dx,1.0,-dz).normalized()
	return Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,heading)
