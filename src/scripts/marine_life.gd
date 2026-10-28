extends Node3D
## Sparse, local animal encounters. All motion uses the caller's simulation clock.
const Ocean = preload("res://scripts/ocean_config.gd")
const Art = preload("res://scripts/marine_life_art.gd")
const FORMS := Art.FORMS
const SPECIES_NAMES := ["岸蟹","海胆","海参","清洁虾","海马","乌贼","绿海龟"]
const COUNTS := [[4,3,2,3,2,0,0],[0,4,3,2,0,1,0],[0,0,3,3,0,2,0],[3,3,0,2,0,1,0],[0,4,0,3,3,1,1],[3,4,3,0,0,1,0],[3,3,2,0,2,0,1]]
const DRAW_DISTANCE := 90.0
var organisms: Array[Dictionary] = []
var batches: Array[MultiMeshInstance3D] = []
var _materials: Dictionary = {}
var _ignored: Array[RID] = []
var _scenery_exclusions: Array[RID] = []
var _wreck: Node3D
var _last_time := -INF

static func build(parent: Node3D, ignored_bodies: Array[RID] = [], wreck: Node3D = null) -> Node3D:
	var result = load("res://scripts/marine_life.gd").new()
	result.name = "MarineLife"
	result._ignored = ignored_bodies
	result._wreck = wreck
	parent.add_child(result)
	result._scenery_exclusions.assign(ignored_bodies)
	for collider: Node in parent.find_children("TerrainCollision","StaticBody3D",true,false):
		result._scenery_exclusions.append(collider.get_rid())
	result._populate()
	return result

func _populate() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 917641
	var areas: Array = Ocean.exploration_areas()
	var placed_by_species: Dictionary = {}
	for kind: String in FORMS:
		_materials[kind] = Art.material(kind)
		placed_by_species[kind] = 0
	for site in range(areas.size()):
		var area: Dictionary = areas[site]
		var region := Node3D.new()
		region.name = "Site%d" % site
		region.position = to_local(Vector3(area.center.x,Ocean.seabed_height(area.center.x,area.center.z),area.center.z))
		add_child(region)
		for form in range(FORMS.size()):
			var kind: String = FORMS[form]
			var count: int = COUNTS[site][form]
			if count == 0:
				continue
			var residents: Array[Dictionary] = []
			for index in range(count):
				var pose: Transform3D = _find_home(area,site,form,index,random)
				if not pose.origin.is_finite():
					push_warning("No clear seabed habitat for %s at site %d" % [kind,site])
					continue
				residents.append({"kind":kind,"site":site,"home":pose.origin,"basis":pose.basis,"phase":random.randf()*TAU,"scale":random.randf_range(.87,1.12),"grounded":form<4,"hover":_hover(form)})
			if residents.is_empty():
				continue
			var visual := MultiMeshInstance3D.new()
			visual.name = kind
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.use_custom_data = true
			multi.mesh = Art.mesh(kind)
			multi.instance_count = residents.size()
			visual.multimesh = multi
			visual.material_override = _materials[kind]
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.visibility_range_end = 140.0 if form == 6 else DRAW_DISTANCE
			visual.visibility_range_end_margin = 14.0
			region.add_child(visual)
			batches.append(visual)
			for index in range(residents.size()):
				var item: Dictionary = residents[index]
				item["visual"] = visual
				item["index"] = index
				multi.set_instance_custom_data(index,Color(float(item.phase)/TAU,0,0,1))
				multi.set_instance_color(index,Color.WHITE)
				organisms.append(item)
				placed_by_species[kind] += 1
	set_meta("species",PackedStringArray(FORMS))
	set_meta("species_counts",placed_by_species)
	set_meta("instance_count",organisms.size())
	set_meta("draw_batches",batches.size())
	set_meta("site_count",areas.size())
	set_meta("decorative_only",true)
	set_meta("no_collision",true)
	set_meta("external_clock_only",true)
	reset()

func reset() -> void:
	_last_time = -INF
	animate(0.0,Vector3.ZERO)
	for batch: MultiMeshInstance3D in batches:
		batch.visible = true

func animate(time: float, viewer: Vector3) -> void:
	for batch: MultiMeshInstance3D in batches:
		batch.visible = batch.global_position.distance_to(viewer) < batch.visibility_range_end+80.0
	if time == _last_time:
		return
	_last_time = time
	for material: ShaderMaterial in _materials.values():
		material.set_shader_parameter("life_clock",time)
	for item: Dictionary in organisms:
		var form: int = FORMS.find(item.kind)
		var phase: float = float(item.phase)
		var point: Vector3 = item.home
		var frame: Basis = item.basis
		match form:
			0:
				point += frame*Vector3(sin(time*.27+phase)*.12,0,0)
			3:
				point += frame*Vector3(0,.015*sin(time*1.2+phase),.045*sin(time*.65+phase))
			4:
				point += Vector3(.06*sin(time*.55+phase),.055*sin(time*.7+phase),0)
				frame = frame*Basis(Vector3.RIGHT,sin(time*.45+phase)*.045)
			5, 6:
				var rate: float = .21 if form == 5 else .11
				var radius: float = 1.05 if form == 5 else 3.4
				var angle: float = time*rate+phase
				point += Vector3(cos(angle)*radius,sin(time*.43+phase)*.12,sin(angle)*radius)
				frame = Basis.looking_at(Vector3(-sin(angle),0,cos(angle)),Vector3.UP)
		var visual: MultiMeshInstance3D = item.visual
		var world_pose := Transform3D(frame.scaled(Vector3.ONE*float(item.scale)),point)
		item["world_transform"] = world_pose
		visual.multimesh.set_instance_transform(item.index,visual.global_transform.affine_inverse()*world_pose)

func nearby_species(viewer: Vector3, max_distance: float = 5.0) -> String:
	if max_distance<=0.0:
		return ""
	var closest: float = max_distance
	var found := ""
	for item: Dictionary in organisms:
		var visual: MultiMeshInstance3D = item.visual
		if not visual.is_visible_in_tree():
			continue
		var point: Vector3 = (item.world_transform as Transform3D)*visual.multimesh.mesh.get_aabb().get_center()
		var distance: float = viewer.distance_to(point)
		if distance>=closest:
			continue
		var query := PhysicsRayQueryParameters3D.create(viewer,point,1,_ignored)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		closest = distance
		found = SPECIES_NAMES[FORMS.find(item.kind)]
	return found

func _find_home(area: Dictionary, site: int, form: int, index: int, random: RandomNumberGenerator) -> Transform3D:
	var center: Vector3 = area.center
	# Separate little colonies occupy the flanks, leaving the central landmark approach open.
	for attempt in range(128):
		var cluster: int = posmod(form+site,3)
		var angle: float = [-2.2,.9,2.3][cluster]+float(site)*.31+float(attempt)*.18
		var reach: float = minf(float(area.radius)*.68,25.0+float(cluster)*9.0) if attempt<12 else float(area.radius)*(.34+float((attempt/8)%6)*.105)
		var point: Vector3 = center+Vector3(sin(angle)*reach,0,cos(angle)*reach)
		point += Vector3((float(index)-1.0)*2.7+random.randf_range(-.5,.5),0,random.randf_range(-2.5,2.5))
		point.y = Ocean.seabed_height(point.x,point.z)
		var normal := Vector3(Ocean.seabed_height(point.x-.6,point.z)-Ocean.seabed_height(point.x+.6,point.z),1.2,Ocean.seabed_height(point.x,point.z-.6)-Ocean.seabed_height(point.x,point.z+.6)).normalized()
		if normal.y < .97 and form < 5:
			continue
		var yaw: float = random.randf_range(-PI,PI)
		var frame: Basis = Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,yaw) if form<4 else Basis(Vector3.UP,yaw)
		point.y += _hover(form)
		if form<4:
			point.y += _ground_correction(point,frame,form)
		if not _clear_habitat(point,frame,form):
			continue
		return Transform3D(frame,point)
	return Transform3D(Basis.IDENTITY,Vector3(INF,INF,INF))

func _clear_habitat(point: Vector3, frame: Basis, form: int) -> bool:
	if _wreck != null and _wreck.contains_point(point,6.0):
		return false
	if form>=5:
		var footprint: float = 2.3 if form==5 else 5.2
		for index in range(12):
			var angle: float = float(index)*TAU/12.0
			var sample: Vector3 = point+Vector3(sin(angle)*footprint,0,cos(angle)*footprint)
			if point.y-Ocean.seabed_height(sample.x,sample.z)<(.65 if form==5 else 1.3):
				return false
	for destination: Dictionary in Ocean.DIVE_SITES:
		if point.distance_to(destination.origin+Vector3(0,-6,25)) < 12.0:
			return false
	var size: Vector3 = [Vector3(2.0,.62,2.0),Vector3(1.55,1.1,1.55),Vector3(.8,.50,2.1),Vector3(1.4,.50,2.4),Vector3(.7,1.8,1.0),Vector3(3.6,.9,4.5),Vector3(10.2,1.8,10.5)][form]
	var center: Vector3 = [Vector3(0,.27,-.08),Vector3(0,.45,0),Vector3(0,.24,0),Vector3(0,.25,-.25),Vector3(0,.75,-.08),Vector3(0,.14,-.15),Vector3(0,.25,-.10)][form]
	# Reject emergent island terrain, including the whole scaled animal and its bob.
	var upper_extent: float = (absf(frame.x.y)*size.x+absf(frame.y.y)*size.y+absf(frame.z.y)*size.z)*0.56
	if point.y+(frame*center).y*1.12+upper_extent+0.18 > -1.0:
		return false
	var shape := BoxShape3D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(frame,point+frame*center)
	query.collision_mask = 1
	# Terrain is sampled under the actual organism; the volume checks solid scenery.
	query.exclude = _scenery_exclusions
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _ground_correction(point: Vector3,frame: Basis,form: int) -> float:
	var vertices: PackedVector3Array = Art.mesh(FORMS[form]).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var correction := -INF
	for index in range(0,vertices.size(),3):
		var world: Vector3 = point+frame*(vertices[index]*1.12)
		correction = maxf(correction,Ocean.seabed_height(world.x,world.z)+.065-world.y)
	return correction

static func _hover(form: int) -> float:
	return [.10,.12,.12,.12,.45,2.0,6.0][form]
