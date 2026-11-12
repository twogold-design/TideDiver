extends SceneTree
const DiveFixture = preload("res://tests/dive_fixture.gd")
const Entry = preload("res://scripts/dive_entry.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass
var checks := 0
var failures := 0
var game: Node3D

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func run() -> void:
	for join: float in [.45,1.55]:
		var before: Vector3 = (Entry.position_at(join)-Entry.position_at(join-.001))/.001
		var after: Vector3 = (Entry.position_at(join+.001)-Entry.position_at(join))/.001
		check(before.distance_to(after)<.08,"Continuous velocity at entry phase boundary "+str(join))
	check(Entry.position_at(3.2)==Vector3(0,-6,25),"Entry keeps the safe underwater destination")
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.smoke_mode = true
	game.start_dive(true,false,game.Ocean.site_index("pearl_atoll"))
	await physics_frame
	var air: float = game.oxygen
	var initial_save: Dictionary = game.progress._save_data().duplicate(true)
	var previous: Vector3 = game.player.position
	var previous_camera: Vector3 = game.camera.position
	var continuous := true
	var camera_clear := true
	var submerged := false
	var ripple_seen := false
	var lens_seen := false
	var captures := {1:"ready",42:"push-off",79:"splash",111:"submerged",155:"settling",192:"swimming"}
	root.size = Vector2i(1440,900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for frame in range(1,193):
		game._physics_process(1.0/60.0)
		continuous = continuous and game.player.position.distance_to(previous)<.2 and game.camera.position.distance_to(previous_camera)<.3
		previous = game.player.position
		previous_camera = game.camera.position
		var query := PhysicsRayQueryParameters3D.create(game.player.position+Vector3.UP*.25,game.camera.position,1,[game.player.get_rid()])
		camera_clear = camera_clear and game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		submerged = submerged or (game.camera.position.y<-.5 and game.player.position.y<-2)
		lens_seen = lens_seen or game.entry_lens.visible
		for effect: Dictionary in game.effects:
			ripple_seen = ripple_seen or effect.get("entry_ripple",false)
		if frame==100:
			game.toggle_pause()
			check(not game.entry_lens.visible,"Pause hides the entry water film immediately")
			var time: float = game.entry_time
			game._physics_process(.4)
			check(game.entry_time==time and game.player.position==previous,"Pausing freezes the entry sequence")
			game.toggle_pause()
		if "--capture-entry" in OS.get_cmdline_user_args() and captures.has(frame):
			await process_frame
			await RenderingServer.frame_post_draw
			var file: String = "user://entry-"+captures[frame]+".png"
			check(root.get_texture().get_image().save_png(file)==OK,"Capture "+captures[frame])
			print("CAPTURE: "+ProjectSettings.globalize_path(file))
	# Floating point accumulation may stop just short of 3.2 by one ulp.
	game._update_entry(.00001)
	check(continuous,"Diver and camera move smoothly at 60 FPS")
	check(camera_clear,"The following view stays clear of scenery throughout the atoll entry")
	check(submerged and ripple_seen and lens_seen,"Real camera immersion, world-space ripples and transient water film are present")
	var final_camera: Transform3D = game.camera.transform
	game._update_swim_camera()
	check(final_camera.origin.distance_to(game.camera.position)<.001 and final_camera.basis.is_equal_approx(game.camera.basis),"Animated camera hands over to the actual swimming camera without a cut")
	check(not game.entry_active and not game.entry_lens.visible and game.oxygen==air and game.depth_record==0,"Swimming resumes without entry overlays or air/depth rewards")
	check(game.progress._save_data()==initial_save,"Entry visuals do not alter saved progression")
	game.state = "dock"
	game.start_dive(true,false,5)
	game._update_entry(1.9)
	game.toggle_pause()
	check(not game.entry_lens.visible,"Pausing during entry hides water film in the same frame")
	DiveFixture.visit(game,5,true)
	check(not game.entry_lens.visible and not game.entry_active,"Direct Test travel leaves no entry film")
	game.state = "dock"
	game.start_dive(true,false,5)
	game._update_entry(1.9)
	game.finish_dive()
	check(not game.entry_lens.visible,"Returning to shore clears water film immediately")
	game.free()
	await process_frame
	print("%s: Tide Diver entry immersion (%d checks)." % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)
