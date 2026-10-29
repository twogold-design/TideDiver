extends SceneTree
const Ocean = preload("res://scripts/ocean_config.gd")
const Art = preload("res://scripts/reef_fish_art.gd")
const Coral = preload("res://scripts/coral_garden.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+description)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	game.start_dive(false,false)
	var reef: Node3D = game.reef_fish
	var before: Dictionary = game.progress._save_data().duplicate(true)
	check(reef.residents.size() == 68 and reef.hosts.size() == 6 and reef.batches.size() == 5,"Six anemone colonies and five separate reef species are present in the real ocean")
	var clown_pairs := {}
	var safe := true
	var corals: Node3D = game.ocean_root.get_node("OuterOcean/amber_reef/CoralGarden")
	var visible_motion := false
	var snapshot: Array = []
	for time: float in [0.0,5.0,23.0,100.0]:
		reef.animate(time,reef.global_position)
		var poses: Array = []
		for fish: Dictionary in reef.residents:
			var pose: Transform3D = fish.visual.global_transform*fish.visual.multimesh.get_instance_transform(fish.index)
			poses.append(pose)
			var point: Vector3 = pose.origin
			safe = safe and point.is_finite() and point.y < -1 and point.y > Ocean.seabed_height(point.x,point.z)+.3
			if fish.kind == "clown":
				var host: Vector3 = reef.to_global(reef.hosts[fish.host])
				safe = safe and point.distance_to(host) < 1.2
				if time == 0:
					clown_pairs[fish.host] = int(clown_pairs.get(fish.host,0))+1
			# Coral is visual geometry, so use its actual transformed mesh bounds.
			for colony: MultiMeshInstance3D in corals.get_children():
				for i in range(colony.multimesh.instance_count):
					var coral_pose: Transform3D = colony.global_transform*colony.multimesh.get_instance_transform(i)
					var coral_bounds: AABB = coral_pose*colony.multimesh.mesh.get_aabb()
					safe = safe and not coral_bounds.grow(.25).has_point(point)
		if snapshot.is_empty():
			snapshot = poses
		else:
			visible_motion = visible_motion or poses != snapshot
	check(safe,"Animated residents stay submerged, above terrain, outside coral bounds and close to their own host")
	check(clown_pairs.size() == 6 and clown_pairs.values().all(func(count): return count == 2),"Clownfish live in pairs around six actual host anemones")
	check(visible_motion,"Reef fish actually swim as the game clock advances")
	var fish: Dictionary = reef.residents[0]
	var point: Vector3 = fish.visual.global_transform*fish.visual.multimesh.get_instance_transform(fish.index).origin
	check(reef.nearby_species(point+Vector3.UP*.1,game.player.get_rid()) == "小丑鱼","Close observation identifies the actual animated clownfish")
	game.player.position = point+Vector3(0,2,3)
	game._physics_process(.02)
	game.toggle_pause()
	var frozen: Transform3D = fish.visual.multimesh.get_instance_transform(fish.index)
	var clock_before: float = reef._material.get_shader_parameter("school_clock")
	game._physics_process(2.0)
	check(fish.visual.multimesh.get_instance_transform(fish.index) == frozen and reef._material.get_shader_parameter("school_clock") == clock_before,"Pause freezes both resident transforms and tail animation")
	game.toggle_pause()
	check(game.progress._save_data() == before and game.cargo.is_empty(),"Habitat observation and animation do not modify the player save or inventory")
	var canyon: Node3D = game.canyon_root
	var traces: MultiMeshInstance3D = canyon.get_node("CurrentTraces")
	check(traces.multimesh.instance_count == 480 and traces.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() > 0,"Natural current uses batched soft-edged ribbons, suspended matter and bubbles")
	canyon.animate(12.0,Ocean.CANYON_CENTER)
	check(canyon.current_material.get_shader_parameter("flow_clock") == 12.0 and not canyon.current_material.shader.code.contains("TIME"),"Natural current respects the simulation clock and pause")
	await _test_vegetation()
	_test_atoll()
	if "--capture-habitats" in OS.get_cmdline_user_args():
		await _captures()
	game.free()
	await process_frame
	print("%s: Tide Diver reef residents and natural current (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _capture(label: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://"+label+".png") == OK,"Capture "+label)

func _test_vegetation() -> void:
	var meadow: Node3D = game.reef_plants
	check(meadow.roots.size()==235 and meadow.get_child_count()==2,"The actual reef has 235 rooted grass and ribbon-algae clumps in only two draw batches")
	var grounded := true
	var lane_clear := true
	for point: Vector3 in meadow.roots:
		grounded = grounded and absf(point.y-Ocean.seabed_height(point.x,point.z))<.001
		var local: Vector3 = point-meadow.global_position
		lane_clear = lane_clear and absf(local.x-sin((local.z+6)*.055)*6.0)>6.9
	check(grounded and lane_clear,"Plant roots meet the seabed and leave the central sand route and clownfish hosts open")
	check(meadow.find_children("*","CollisionObject3D",true,false).is_empty(),"Decorative vegetation does not obstruct movement or fishing hooks")
	var fan: Mesh = Coral._coral_mesh(2)
	var hard: Mesh = Coral._coral_mesh(0)
	check(fan.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2][0].x==1 and hard.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2][0].x==0,"Only soft sea fans carry the coral bending mask; hard branching coral remains rigid")
	game.player.position = meadow.roots[0]+Vector3.UP*3
	game._animate_ocean(0)
	game.toggle_pause()
	var clock_before: float = meadow.sway_material.get_shader_parameter("plant_clock")
	var fan_before: float = Coral.material().get_shader_parameter("reef_clock")
	var host_before: float = game.reef_fish._host_material.get_shader_parameter("plant_clock")
	game._physics_process(3.0)
	check(meadow.sway_material.get_shader_parameter("plant_clock")==clock_before and Coral.material().get_shader_parameter("reef_clock")==fan_before and game.reef_fish._host_material.get_shader_parameter("plant_clock")==host_before,"Pause freezes grass, sea fans and anemone tentacles on the actual game clock")
	game.toggle_pause()
	var leaves: MultiMeshInstance3D = meadow.get_node("RibbonAlgae")
	var target: Vector3 = meadow.global_transform*leaves.multimesh.get_instance_transform(0).origin+Vector3.UP*.7
	game.hud.visible = false
	game.player.visible = false
	game.camera.position = target+Vector3(2.0,1.2,3.0)
	game.camera.look_at(target)
	game._apply_underwater_lighting(-game.camera.position.y)
	meadow.animate(0,target)
	await process_frame
	await RenderingServer.frame_post_draw
	var before: Image = root.get_texture().get_image()
	meadow.animate(4.0,target)
	await process_frame
	await RenderingServer.frame_post_draw
	var after: Image = root.get_texture().get_image()
	var changed := 0
	for y in range(before.get_height()/4,before.get_height()*3/4,3):
		for x in range(before.get_width()/4,before.get_width()*3/4,3):
			var a: Color = before.get_pixel(x,y)
			var b: Color = after.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.025:
				changed += 1
	check(changed>60,"Real GPU frames show rooted leaves bending as the plant clock advances (%d changed samples)" % changed)
	meadow.animate(4,Vector3(450,-20,450))
	check(not meadow.visible,"Reef vegetation is culled when the diver visits another area")
	game.hud.visible = true
	game.player.visible = true

func _test_atoll() -> void:
	var atoll: Node3D = game.ocean_root.get_node("OuterOcean/pearl_atoll/NaturalAtoll")
	var grounded := true
	var channel_clear := true
	for point: Vector3 in atoll.get_meta("roots"):
		grounded = grounded and absf(point.y-Ocean.seabed_height(point.x,point.z))<.001
		var local: Vector3 = point-atoll.global_position
		channel_clear = channel_clear and absf(wrapf(atan2(local.z,local.x)-PI*.5,-PI,PI))>=.48
	check(grounded and channel_clear,"Atoll shell beds and plants meet the actual seabed and leave the southern lagoon entrance clear")
	check(atoll.find_children("*","CollisionObject3D",true,false).is_empty(),"Small atoll decorations do not introduce invisible movement or fishing barriers")
	var leaves: MultiMeshInstance3D = atoll.get_node("LagoonGrass")
	if game.state == "paused":
		game.toggle_pause()
	game._animate_ocean(0)
	var clock_before: float = leaves.material_override.get_shader_parameter("plant_clock")
	game.toggle_pause()
	game._physics_process(2.0)
	check(leaves.material_override.get_shader_parameter("plant_clock")==clock_before,"Atoll vegetation freezes with the real game pause")
	game.toggle_pause()
	game._physics_process(.25)
	check(leaves.material_override.get_shader_parameter("plant_clock")>clock_before,"Atoll vegetation resumes when the game clock advances")

func _captures() -> void:
	root.size = Vector2i(1440,900)
	game.hud.visible = false
	game.player.visible = false
	var reef: Node3D = game.reef_fish
	var host: Vector3 = reef.to_global(reef.hosts[2])
	game.player.position = host+Vector3(0,1,3)
	game.camera.position = host+Vector3(2.4,1.7,3.1)
	game.camera.look_at(host+Vector3.UP*.65)
	game._animate_ocean(0)
	game._apply_underwater_lighting(-game.camera.position.y)
	reef.animate(4.0,game.camera.position)
	await _capture("reef-clownfish")
	game.camera.position = host+Vector3(10,7,12)
	game.camera.look_at(host+Vector3(7,3,-2))
	await _capture("reef-community")
	var garden: Node3D = game.ocean_root.get_node("OuterOcean/amber_reef/CoralGarden")
	for form: String in ["Staghorn","TableCoral","BrainCoral","SeaFan"]:
		var visual: MultiMeshInstance3D = garden.get_node(form)
		var target: Vector3 = visual.global_transform*visual.multimesh.get_instance_transform(0).origin+Vector3.UP*.6
		game.player.position = target
		game.camera.position = target+Vector3(2.7,1.7,3.2)
		game.camera.look_at(target)
		game._animate_ocean(0)
		game._apply_underwater_lighting(-game.camera.position.y)
		await _capture("reef-detail-"+form.to_lower())
	var wreck: Node3D = game.explorable_wreck
	game.player.position = wreck.to_global(Vector3(0,4.7,7))
	game.camera.position = game.player.position
	game.camera.look_at(wreck.to_global(Vector3(0,4.7,-8)))
	game._animate_ocean(0)
	game._apply_underwater_lighting(-game.camera.position.y)
	await _capture("wreck-mixed-fish")
	game.player.position = wreck.to_global(Vector3(22,22,42))
	game.camera.position = game.player.position
	game.camera.look_at(wreck.to_global(Vector3(0,10,0)))
	game._animate_ocean(0)
	game._apply_underwater_lighting(-game.camera.position.y)
	await _capture("wreck-steel-overview")
	game.camera.position = wreck.to_global(Vector3(0,6,14))
	game.player.position = game.camera.position
	game.camera.look_at(wreck.to_global(Vector3(4.7,4,23)))
	game._apply_underwater_lighting(-game.camera.position.y)
	await _capture("wreck-engine-room")
	game.camera.position = wreck.to_global(Vector3(0,13,7))
	game.player.position = game.camera.position
	game.camera.look_at(wreck.to_global(Vector3(0,15,14)))
	game._apply_underwater_lighting(-game.camera.position.y)
	await _capture("wreck-bridge")
	game.camera.position = Vector3(245,Ocean.seabed_height(245,276)+16,282)
	game.player.position = game.camera.position
	game.camera.look_at(Vector3(245,Ocean.seabed_height(245,240)+5,240))
	game._animate_ocean(0)
	game._apply_underwater_lighting(-game.camera.position.y)
	await _capture("atoll-lagoon")
	game.player.position = Vector3(Ocean.canyon_center_x(-325),-78,-325)
	game.camera.position = game.player.position
	game.camera.look_at(game.player.position+Ocean.canyon_tangent(-325)*15.0+Vector3(0,-3,0))
	game._animate_ocean(0)
	game.environment.fog_density = .010
	game._apply_underwater_lighting(78.0)
	canyon_clock(7.0)
	await _capture("canyon-natural-current")
	game.camera.position = Vector3(Ocean.canyon_center_x(-310),-108,-310)
	game.player.position = game.camera.position
	game.camera.look_at(Vector3(Ocean.canyon_center_x(-265),-108,-265))
	game._apply_underwater_lighting(108.0)
	await _capture("canyon-sand-and-talus")
	game.camera.position = Vector3(Ocean.canyon_center_x(-290)+8,-88,-290)
	game.player.position = game.camera.position
	game.camera.look_at(Vector3(Ocean.canyon_center_x(-275)+31,-80,-275))
	game._apply_underwater_lighting(88.0)
	await _capture("canyon-eroded-wall")

func canyon_clock(time: float) -> void:
	game.canyon_root.animate(time,game.player.position)
