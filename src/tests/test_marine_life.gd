extends SceneTree
## Sparse decorative species, real habitat clearance, external-clock motion and GPU silhouettes.
const Ocean = preload("res://scripts/ocean_config.gd")
const Marine = preload("res://scripts/marine_life.gd")
const Art = preload("res://scripts/marine_life_art.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var life: Node3D
var memory: MemoryProgression
var checks := 0
var failures := 0
var output: String

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+description)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: Marine organism tests require the actual GPU renderer.")
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	await process_frame
	game.start_dive(false,false)
	await physics_frame
	await process_frame
	life = game.ocean_root.get_node_or_null("MarineLife")
	_check(life != null,"The actual ocean includes its new decorative marine animals")
	if life != null:
		output = ProjectSettings.globalize_path("res://../.runtime/marine-life-checks")
		DirAccess.make_dir_recursive_absolute(output)
		var before: Dictionary = memory._save_data().duplicate(true)
		_test_population_and_resources()
		_test_habitats_and_motion()
		_test_observation_distance()
		await _test_rendered_species()
		await _test_pause_and_reset()
		_test_capture_isolation()
		_check(game.fish.size() == 167 and game.fish_population_count() == 167 and game.pickups.size() == 74,"Ambient ecology preserves the original sparse huntable population and existing pickups")
		_check(game.cargo.is_empty() and memory._save_data() == before and memory.saves == 0,"Viewing, animation, GM and firing through ambient animals never change cargo or durable progress")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver ambient marine ecology (%d checks)." % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)

func _test_population_and_resources() -> void:
	var forms: PackedStringArray = life.get_meta("species",PackedStringArray())
	_check(forms == PackedStringArray(Art.FORMS) and forms.size()==7,"Seven distinct added species include crabs, urchins, cucumbers, shrimp, seahorses, cuttlefish and turtles")
	var counts: Dictionary = life.get_meta("species_counts",{})
	var actual_count := 0
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	var bounded_batches := true
	for visual: MultiMeshInstance3D in life.batches:
		actual_count += visual.multimesh.instance_count
		meshes[visual.multimesh.mesh.get_instance_id()] = true
		materials[visual.material_override.get_instance_id()] = true
		bounded_batches = bounded_batches and visual.multimesh.instance_count <= 4 and visual.visibility_range_end > 0 and visual.visibility_range_end <= 140 and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check(actual_count==life.organisms.size() and actual_count==75 and int(life.get_meta("instance_count",0))==actual_count,"The seven habitats hold seventy-five ambient animals in restrained local encounters")
	_check(meshes.size()==7 and materials.size()==7 and life.batches.size()<=35 and bounded_batches,"Species share seven original meshes and materials with at most four residents per culled batch")
	_check(int(counts.get("GreenTurtle",0))==2 and int(counts.get("Cuttlefish",0))==6,"Only two turtles and six small cuttlefish occupy the entire ocean")
	_check(not _has_collision(life) and bool(life.get_meta("decorative_only",false)),"Ambient animals add no physical obstacles, pickup areas or combat targets")
	for kind: String in Art.FORMS:
		var mesh: ArrayMesh = Art.mesh(kind)
		var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var motion: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var finite := not points.is_empty() and points.size()==normals.size() and points.size()==motion.size()
		var moving_parts := 0
		for index in range(points.size()):
			finite = finite and points[index].is_finite() and normals[index].is_finite() and normals[index].length()>.1
			if motion[index].a > .1:
				moving_parts += 1
		_check(finite and points.size()>=120 and mesh.get_aabb().size.length()>.7 and (moving_parts>0 or kind=="SeaUrchin"),"The %s silhouette has finite organic surfaces and anatomical appendage motion weights" % kind)

func _test_habitats_and_motion() -> void:
	var present: Dictionary = {}
	var clear := true
	var local := true
	var above_ground := true
	var ground_min := INF
	var first_bad := ""
	for time: float in [0.0,12.0,47.0,210.0]:
		life.animate(time,Vector3.ZERO)
		for item: Dictionary in life.organisms:
			present[int(item.site)] = true
			var visual: MultiMeshInstance3D = item.visual
			var actual: Transform3D = visual.global_transform*visual.multimesh.get_instance_transform(item.index)
			var area: Dictionary = Ocean.exploration_areas()[int(item.site)]
			local = local and Vector2(actual.origin.x-area.center.x,actual.origin.z-area.center.z).length()<float(area.radius)+3
			local = local and not game.explorable_wreck.contains_point(actual.origin,4.0)
			clear = clear and _sphere_clear(actual*Vector3(0,.25,0),.10)
			var vertices: PackedVector3Array = visual.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for index in range(0,vertices.size(),6):
				var point: Vector3 = actual*vertices[index]
				var clearance: float = point.y-Ocean.seabed_height(point.x,point.z)
				if clearance < ground_min:
					ground_min = clearance
					first_bad = "%s site%d at %s" % [item.kind,item.site,point]
				above_ground = above_ground and clearance >= -.015
	_check(present.size()==7 and local,"All seven sites contain localized ecology that stays outside the hollow wreck and its entrances")
	_check(clear and above_ground,"Actual animated animal geometry remains above the real seabed and outside solid rock: minimum %.4f, %s" % [ground_min,first_bad])
	life.animate(0.0,Vector3.ZERO)
	var first: Array = _snapshot()
	life.animate(1.5,Vector3.ZERO)
	var moved: Array = _snapshot()
	_check(first!=moved,"The external simulation clock advances modest animal movement and appendage animation")
	life.animate(1.5,Vector3.ZERO)
	_check(_snapshot()==moved,"An unchanged simulation clock freezes every instance and all shared appendage shader clocks")
	life.animate(1.5,Vector3(5000,0,5000))
	var hidden := true
	for visual: MultiMeshInstance3D in life.batches:
		hidden = hidden and not visual.visible
	_check(hidden,"Far-away local animal colonies are culled instead of drawing across the ocean")

func _test_rendered_species() -> void:
	game.hud.visible = false
	game.player.get_child(0).visible = false
	for kind: String in Art.FORMS:
		var resident: Dictionary = {}
		for item: Dictionary in life.organisms:
			if item.kind==kind:
				resident=item
				break
		if resident.is_empty():
			_check(false,"A visible natural resident exists for "+kind)
			continue
		life.animate(6.0,resident.home)
		var visual: MultiMeshInstance3D = resident.visual
		var pose: Transform3D = visual.global_transform*visual.multimesh.get_instance_transform(resident.index)
		var center: Vector3 = pose*visual.multimesh.mesh.get_aabb().get_center()
		game.player.position = center+Vector3(1,1,2)
		game.camera.position = center+Vector3(2.4,1.8,3.0)*(1.3 if kind=="GreenTurtle" else .65)
		game.camera.look_at(center)
		game._apply_underwater_lighting(maxf(0,-game.camera.position.y))
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		_check(visual.is_visible_in_tree() and game.camera.is_position_in_frustum(center) and not frame.is_empty() and frame.save_png(output.path_join(kind+".png"))==OK,"A close actual GPU frame shows the natural "+kind+" silhouette")
		var center_luma := 0.0
		for y in range(frame.get_height()/2-4,frame.get_height()/2+5):
			for x in range(frame.get_width()/2-4,frame.get_width()/2+5):
				var color: Color = frame.get_pixel(x,y)
				center_luma += color.r*.2126+color.g*.7152+color.b*.0722
		_check(center_luma/81.0>.035,"The actual "+kind+" body has readable colored shading rather than a black material silhouette")
	game.hud.visible = true
	game.player.get_child(0).visible = true

func _test_observation_distance() -> void:
	var resident: Dictionary = {}
	for item: Dictionary in life.organisms:
		if item.kind=="GreenTurtle":
			resident=item
			break
	life.animate(31.0,resident.home)
	var visual: MultiMeshInstance3D = resident.visual
	var pose: Transform3D = visual.global_transform*visual.multimesh.get_instance_transform(resident.index)
	var actual: Vector3 = pose*visual.multimesh.mesh.get_aabb().get_center()
	_check(life.nearby_species(actual+Vector3.UP*.10,.20)=="绿海龟" and life.nearby_species(actual+Vector3.UP*.35,.20).is_empty(),"Observation names use the actual animated turtle position and respect the requested distance")
	visual.visible=false
	_check(life.nearby_species(actual+Vector3.UP*.10,.20).is_empty(),"A hidden resident cannot produce an observation prompt")
	visual.visible=true

func _test_pause_and_reset() -> void:
	game.state="dive"
	game.entry_active=false
	game.player.position=Vector3(400,-20,400)
	game.player.velocity=Vector3.ZERO
	game._physics_process(.02)
	game.toggle_pause()
	var before: Array = _snapshot()
	game.set_physics_process(true)
	await physics_frame
	for frame in range(12):
		await physics_frame
	game.set_physics_process(false)
	_check(game.state=="paused" and _snapshot()==before,"Real pause freezes ambient instance transforms and every appendage shader")
	game.open_gm_menu()
	game._physics_process(1.0)
	_check(game.gm_menu_open and _snapshot()==before,"An open GM menu also freezes the ambient ecology")
	game.close_gm_menu()
	game.toggle_pause()
	life.reset()
	var original: Array = _snapshot()
	life.animate(12.0,Vector3.ZERO)
	life.reset()
	_check(_snapshot()==original,"Reset restores the deterministic original ambient poses without creating more animals")

func _test_capture_isolation() -> void:
	for item: Dictionary in game.fish:
		item.alive=false
		item.node.visible=false
	var resident: Dictionary = life.organisms[0]
	life.animate(0,resident.home)
	var visual: MultiMeshInstance3D = resident.visual
	var pose: Transform3D = visual.global_transform*visual.multimesh.get_instance_transform(resident.index)
	var target: Vector3 = pose*visual.multimesh.mesh.get_aabb().get_center()
	game.player.position=target+Vector3(0,3,6)
	game.camera.position=game.player.position
	game.camera.look_at(target)
	game.yaw=0
	game.shot_cooldown=0
	game.cargo.clear()
	game.shoot()
	var launched: bool = game.projectiles.size()==1
	for step in range(60):
		game._update_projectiles(1.0/60.0)
	_check(launched and game.cargo.is_empty() and game.target_fish().is_empty(),"A physical harpoon aimed through a decorative crab cannot capture it or add warehouse goods")
	for item: Dictionary in life.organisms:
		if item.kind=="GreenTurtle":
			var turtle_visual: MultiMeshInstance3D = item.visual
			var turtle_pose: Transform3D = turtle_visual.global_transform*turtle_visual.multimesh.get_instance_transform(item.index)
			game.player.position=turtle_pose*turtle_visual.multimesh.mesh.get_aabb().get_center()+Vector3.UP*.10
			game.camera.position=game.player.position
			game.camera.look_at(game.player.position+Vector3.FORWARD)
			life.animate(0,game.player.position)
			_check(game.context_hint()=="观察 · 绿海龟","The actual game context displays the nearby ambient species when no pickup or huntable target takes priority")
			break

func _snapshot() -> Array:
	var result: Array = []
	for visual: MultiMeshInstance3D in life.batches:
		result.append(visual.material_override.get_shader_parameter("life_clock"))
		for index in range(visual.multimesh.instance_count):
			result.append(visual.multimesh.get_instance_transform(index))
	return result

func _sphere_clear(point: Vector3,radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius=radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,point)
	query.collision_mask=1
	query.exclude=[game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _has_collision(child):
			return true
	return false
