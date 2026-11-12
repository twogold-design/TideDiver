extends RefCounted
## Test-only positioning. Never included by the release scene export or client package.

static func viewpoint(game: Node, index: int) -> Dictionary:
	var ocean = game.Ocean
	var point: Vector3 = ocean.DIVE_SITES[index].origin + Vector3(0,-9,12)
	var heading := 0.0
	var tilt := -0.12
	match str(ocean.DIVE_SITES[index].id):
		"twin_gates":
			point = Vector3(ocean.canyon_center_x(-325),-78,-325)
			var downstream: Vector3 = ocean.canyon_tangent(point.z)
			heading = atan2(-downstream.x,-downstream.z)
			tilt = -0.20
		"merchant_wreck":
			point = game.explorable_wreck.to_global(Vector3(0,6,36))
			heading = game.explorable_wreck.rotation.y
		"amber_reef":
			point = Vector3(-180,-11,180)
			tilt = -0.25
		"southern_spires":
			point = game.StormSchool.CENTER + Vector3(0,0,37)
		"pearl_atoll":
			point = Vector3(245,ocean.seabed_height(245,276)+12,276)
	if not game._open_water(point):
		var found := false
		for ring in range(1,13):
			for direction in range(8):
				var angle: float = float(direction)*TAU/8.0
				var candidate := point + Vector3(sin(angle)*ring*2.0,ring*1.5,cos(angle)*ring*2.0)
				if ocean.seabed_height(candidate.x,candidate.z)+3 > -6:
					continue
				candidate.y = clampf(candidate.y,ocean.seabed_height(candidate.x,candidate.z)+3,-6)
				if game._open_water(candidate):
					point = candidate
					found = true
					break
			if found:
				break
		if not found:
			point = ocean.DIVE_SITES[index].origin + Vector3(0,-6,25)
	return {"position":point,"yaw":heading,"pitch":tilt}

static func visit(game: Node, index: int, direct: bool = false) -> void:
	assert(index >= 0 and index < game.Ocean.DIVE_SITES.size())
	if game.bestiary_open:
		game.close_bestiary()
	game.splash_player.stop()
	if game.state == "dock":
		game.start_dive(not direct,false,index)
	else:
		game._select_dive_site(false,index)
		game._clear_projectiles()
		game.state = "dive"
	game.touch_input.reset()
	game.diver_bubbles.reset()
	game.entry_lens.visible = false
	game.entry_active = not direct
	game.entry_time = 0.0
	game.entry_splashed = false
	game.player.velocity = Vector3.ZERO
	game.player.rotation = Vector3.ZERO
	game.drift_current = Vector3.ZERO
	game.diver_motion.reset()
	game.diver_knife.reset()
	game.player.get_child(0).visible = true
	game.current_hint = ""
	game.catch_timer = 0.0
	game._clear_loot_feedback()
	game.hit_timer = 0.0
	game.shot_cooldown = 0.0
	game.hurt_cooldown = 0.0
	game.hurt_flash = 0.0
	game.poison_timer = 0.0
	game.hunt_warning_timer = 0.0
	game.hunt_warning = ""
	game.camera.fov = 66
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if direct:
		var pose := viewpoint(game,index)
		game.player.position = pose.position
		game.yaw = pose.yaw
		game.pitch = pose.pitch
		game.player.rotation.y = game.yaw
		game._update_swim_camera()
	else:
		game._update_entry(0.0)
	Input.mouse_mode = game._dive_mouse_mode()
	game.hud.rebuild()
