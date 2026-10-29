extends Node3D
## Local reef residents: paired anemonefish and small schools over the coral banks.
const Ocean = preload("res://scripts/ocean_config.gd")
const Art = preload("res://scripts/reef_fish_art.gd")
const KINDS := ["clown","chromis","butterfly","tang","anthias"]
const NAMES := ["小丑鱼","蓝绿雀鲷","蝴蝶鱼","蓝吊","金花鲈"]
var residents: Array[Dictionary] = []
var hosts: Array[Vector3] = []
var batches: Array[MultiMeshInstance3D] = []
var _material: ShaderMaterial
var _last_time := -INF

static func build(parent: Node3D) -> Node3D:
	var result = load("res://scripts/reef_fish_habitat.gd").new()
	result.name = "ReefFishHabitat"
	parent.add_child(result)
	result.position = Vector3(-180,0,135)
	result._populate()
	return result

func _populate() -> void:
	_material = Art.material()
	# Sand pockets on both sides of the winding central route, beside actual coral.
	for z: float in [-25.0,0.0,25.0]:
		for side: float in [-1.0,1.0]:
			var x: float = sin((z+6.0)*.055)*6.0+side*4.5
			var point := Vector3(x,0,z)
			point.y = Ocean.seabed_height(global_position.x+x,global_position.z+z)+.12
			hosts.append(point)
	var host_visual := MultiMeshInstance3D.new()
	host_visual.name = "HostAnemones"
	var host_batch := MultiMesh.new()
	host_batch.transform_format = MultiMesh.TRANSFORM_3D
	host_batch.mesh = Art.anemone_mesh()
	host_batch.instance_count = hosts.size()
	for index in range(hosts.size()):
		host_batch.set_instance_transform(index,Transform3D(Basis.IDENTITY,hosts[index]))
	host_visual.multimesh = host_batch
	var host_material := StandardMaterial3D.new()
	host_material.vertex_color_use_as_albedo = true
	host_material.roughness = .9
	host_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	host_visual.material_override = host_material
	host_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host_visual.visibility_range_end = 85.0
	add_child(host_visual)
	for kind in KINDS:
		var count: int = {"clown":12,"chromis":24,"butterfly":8,"tang":6,"anthias":18}[kind]
		var visual := MultiMeshInstance3D.new()
		visual.name = kind.capitalize()
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.use_custom_data = true
		batch.mesh = Art.mesh(kind)
		batch.instance_count = count
		visual.multimesh = batch
		visual.material_override = _material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 100.0
		visual.custom_aabb = AABB(Vector3(-50,-70,-50),Vector3(100,70,100))
		add_child(visual)
		batches.append(visual)
		for index in range(count):
			var host: int = index/2 if kind == "clown" else index%hosts.size()
			var home: Vector3 = hosts[host]
			var radius := .45
			var speed := .65
			var size := 1.0
			if kind == "clown":
				home.y += .85
				size = .85 if index%2 == 0 else .66
			else:
				var side: float = -1.0 if host%2 == 0 else 1.0
				home.x += side*(6.0+float(index%3)*1.5)
				home.z += float(index/6)*1.1
				home.y = _orbit_floor(home,3.0)+4.3+float(index%3)*.35
				radius = 1.3+float(index%3)*.4
				speed = .25 if kind in ["butterfly","tang"] else .45
				size = 1.25 if kind in ["butterfly","tang"] else .78
			var phase: float = float(index)*2.39996
			residents.append({"kind":kind,"home":home,"host":host,"radius":radius,"speed":speed,"scale":size,"phase":phase,"visual":visual,"index":index})
			batch.set_instance_custom_data(index,Color(fposmod(phase/TAU,1.0),float(index%5)/5.0,0,1))
			batch.set_instance_color(index,Color.WHITE)
	set_meta("decorative_only",true)
	set_meta("no_collision",true)
	set_meta("species",PackedStringArray(KINDS))
	set_meta("draw_batches",6)
	reset()

func _orbit_floor(point: Vector3, radius: float) -> float:
	var floor_y := -INF
	for index in range(16):
		var angle: float = float(index)*TAU/16.0
		floor_y = maxf(floor_y,Ocean.seabed_height(global_position.x+point.x+sin(angle)*radius,global_position.z+point.z+cos(angle)*radius))
	return floor_y

func reset() -> void:
	_last_time = -INF
	animate(0.0,global_position)

func animate(time: float, viewer: Vector3) -> void:
	visible = Vector2(viewer.x-global_position.x,viewer.z-global_position.z).length() < 155.0
	if not visible or time == _last_time:
		return
	_last_time = time
	_material.set_shader_parameter("school_clock",time)
	for fish: Dictionary in residents:
		var angle: float = time*fish.speed+fish.phase
		var point: Vector3 = fish.home+Vector3(cos(angle)*fish.radius,sin(angle*1.3)*.10,sin(angle)*fish.radius*.65)
		var direction := Vector3(-sin(angle),.13*cos(angle*1.3),cos(angle)*.65)
		var pose := Transform3D(Basis.looking_at(direction.normalized()).scaled(Vector3.ONE*fish.scale),point)
		fish.visual.multimesh.set_instance_transform(fish.index,pose)

func nearby_species(viewer: Vector3, ignored_body: RID) -> String:
	if not is_visible_in_tree():
		return ""
	var closest := 4.0
	var result := ""
	for fish: Dictionary in residents:
		var visual: MultiMeshInstance3D = fish.visual
		var point: Vector3 = visual.global_transform*visual.multimesh.get_instance_transform(fish.index).origin
		var distance: float = viewer.distance_to(point)
		if distance >= closest:
			continue
		if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(viewer,point,1,[ignored_body])).is_empty():
			continue
		closest = distance
		result = NAMES[KINDS.find(fish.kind)]
	return result
