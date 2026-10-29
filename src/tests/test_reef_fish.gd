extends SceneTree
const Ocean = preload("res://scripts/ocean_config.gd")
const Art = preload("res://scripts/reef_fish_art.gd")
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
	var wreck: Node3D = game.explorable_wreck
	game.player.position = wreck.to_global(Vector3(0,4.7,7))
	game.camera.position = game.player.position
	game.camera.look_at(wreck.to_global(Vector3(0,4.7,-8)))
	game._animate_ocean(0)
	game._apply_underwater_lighting(-game.camera.position.y)
	await _capture("wreck-mixed-fish")
	game.player.position = Vector3(Ocean.canyon_center_x(-325),-78,-325)
	game.camera.position = game.player.position
	game.camera.look_at(game.player.position+Ocean.canyon_tangent(-325)*15.0+Vector3(0,-3,0))
	game._animate_ocean(0)
	game.environment.fog_density = .010
	game._apply_underwater_lighting(78.0)
	canyon_clock(7.0)
	await _capture("canyon-natural-current")

func canyon_clock(time: float) -> void:
	game.canyon_root.animate(time,game.player.position)
