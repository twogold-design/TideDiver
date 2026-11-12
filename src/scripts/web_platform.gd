extends Node
## Browser lifecycle integration. The desktop build never creates this node.
var game: Node
var _lock_callback: JavaScriptObject
var _visibility_callback: JavaScriptObject
var _pause_callback: JavaScriptObject
var _mobile_callback: JavaScriptObject
var _mobile_state := ""
var _mobile_time := 0.0
const MAX_3D_PIXELS := 1800000.0
var _stats_time := 0.0
var _render_scene := ""
var _warming_up := true

func _ready() -> void:
	_lock_callback = JavaScriptBridge.create_callback(_on_pointer_lock)
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility)
	_pause_callback = JavaScriptBridge.create_callback(_on_pause)
	_mobile_callback = JavaScriptBridge.create_callback(_on_mobile_command)
	JavaScriptBridge.get_interface("window").tideMobileCommand = _mobile_callback
	var document = JavaScriptBridge.get_interface("document")
	document.addEventListener("pointerlockchange", _lock_callback)
	document.addEventListener("visibilitychange", _visibility_callback)
	document.addEventListener("tide-pause", _pause_callback)
	get_viewport().size_changed.connect(_apply_render_budget)
	_apply_render_budget()
	call_deferred("_prepare_scenes")
	if not OS.is_userfs_persistent():
		game.tell("浏览器未允许保存进度；请使用普通窗口并允许网站存储。", 12)

func _prepare_scenes() -> void:
	# Compile/upload the first-use scene materials behind the existing loading
	# cover, one view per rendered frame. Do not run gameplay or touch the save.
	if game.state == "dock":
		var player_transform: Transform3D = game.player.transform
		var boat_transform: Transform3D = game.boat.transform
		var entry_snapshot := {"dive_origin":game.dive_origin,"entry_time":game.entry_time,"entry_splashed":game.entry_splashed,"yaw":game.yaw,"pitch":game.pitch}
		game.set_physics_process(false)
		game.set_process_input(false)
		game.set_process_unhandled_input(false)
		game.hud.visible = false
		game.player.visible = true
		game.entry_splashed = true # Warm only the view; no sound, particles or gameplay.
		var droplets: Array[MeshInstance3D] = []
		for mesh: SphereMesh in game._entry_water_meshes:
			var droplet := MeshInstance3D.new()
			droplet.mesh = mesh
			droplet.material_override = game._entry_water_material
			game.ocean_root.add_child(droplet)
			droplets.append(droplet)
		# Prepare the first coastal entry only. Other sites share these materials;
		# visiting every site at six animation times blocked startup unnecessarily.
		for index in [0]:
			JavaScriptBridge.eval("document.dispatchEvent(new CustomEvent('tide-loading', {detail:'正在准备近岸入水…'}));",true)
			var origin: Vector3 = game.Ocean.DIVE_SITES[index].origin
			game.dive_origin = origin
			game.boat.position = origin+Vector3(0,0.3,14)
			# The lamp starts affecting the boat during immersion, before the final
			# underwater pose. Render that real path to prepare those shader variants.
			for moment: float in [0.0,1.7,3.19]:
				game.entry_time = moment
				game._update_entry(0.0)
				for i in range(droplets.size()):
					droplets[i].position = game.player.position+Vector3(i*0.2,0.5,0)
				game._animate_ocean(0.0)
				await RenderingServer.frame_post_draw
		for droplet in droplets:
			droplet.free()
		for key: String in entry_snapshot:
			game.set(key,entry_snapshot[key])
		JavaScriptBridge.eval("document.dispatchEvent(new CustomEvent('tide-loading', {detail:'正在准备海边餐厅…'}));",true)
		game.ocean_root.visible = false
		game.restaurant_node.visible = true
		game.player.visible = false
		game._reset_shore_lighting()
		game.environment.fog_enabled = false
		game.camera.fov = 50
		game.camera.position = game.restaurant_node.position+Vector3(22,18,27)
		game.camera.look_at(game.restaurant_node.position+Vector3(0,1,2))
		await RenderingServer.frame_post_draw
		# The editor uses a different camera and translucent floor grid. Prepare
		# that first frame too, without entering layout or creating a draft save.
		game.restaurant_node.set_layout_grid(true)
		game.update_layout_camera()
		await RenderingServer.frame_post_draw
		game.restaurant_node.set_layout_grid(false)
		game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		game.player.transform = player_transform
		game.boat.transform = boat_transform
		game.restaurant_node.visible = false
		game.ocean_root.visible = true
		game.environment.fog_enabled = true
		game._reset_shore_lighting()
		game.camera.fov = 66
		game.camera.position = Vector3(16,-13,29)
		game.camera.look_at(Vector3(0,-23,-10))
		game._animate_ocean(0.0)
		game.hud.visible = true
		game.set_physics_process(true)
		game.set_process_input(true)
		game.set_process_unhandled_input(true)
		await RenderingServer.frame_post_draw
	_warming_up = false
	_publish_mobile_state()
	JavaScriptBridge.eval("window.tideGameReady = true; document.dispatchEvent(new Event('tide-ready'));",true)

func _apply_render_budget() -> void:
	# Limit only the 3D buffer. UI glyphs keep the native display resolution.
	var pixels := Vector2(get_window().size)
	var area := maxf(1.0, pixels.x * pixels.y)
	_render_scene = "restaurant" if game.state in ["restaurant", "service", "service_paused"] else "ocean"
	# The smaller restaurant scene is faster without the extra upscale render pass
	# at normal desktop sizes; only budget it on very large/high-DPI canvases.
	var budget: float = (area if area <= 4500000.0 else 3000000.0) if _render_scene == "restaurant" else MAX_3D_PIXELS
	if game.mobile_controls:
		budget = minf(budget,700000.0)
	get_viewport().scaling_3d_scale = minf(1.0, sqrt(budget / area))
	_publish_render_stats()

func _process(delta: float) -> void:
	if _warming_up:
		return
	if game.mobile_controls:
		_mobile_time += delta
		if _mobile_time >= .1:
			_mobile_time = 0.0
			_publish_mobile_state()
	var scene: String = "restaurant" if game.state in ["restaurant", "service", "service_paused"] else "ocean"
	if scene != _render_scene:
		_apply_render_budget()
	_stats_time += delta
	if _stats_time >= (.1 if game.mobile_controls else 1.0):
		_stats_time = 0.0
		_publish_render_stats()

func _publish_render_stats() -> void:
	var pixels := Vector2(get_window().size)
	var render_scale := get_viewport().scaling_3d_scale
	var stats := {"scale3d": render_scale, "pixels3d": pixels.x * pixels.y * render_scale * render_scale,
		"fps": Engine.get_frames_per_second(), "physicsMs": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
		"drawCalls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"state": game.state, "oxygen": game.oxygen, "rescueResult": game.rescue_result_visible}
	if game.mobile_controls:
		stats["playerPosition"] = [game.player.position.x,game.player.position.y,game.player.position.z]
		stats["yaw"] = game.yaw
		stats["pitch"] = game.pitch
		stats["projectileCount"] = game.projectiles.size()
		stats["shotCooldown"] = game.shot_cooldown
		stats["knifeRemaining"] = game.diver_knife.remaining
		stats["touchMove"] = [game.touch_input.movement.x,game.touch_input.movement.y]
		stats["touchHeld"] = game.touch_input.held.duplicate()
	JavaScriptBridge.eval("window.tideRenderStats = " + JSON.stringify(stats) + ";", true)

func _on_mobile_command(args: Array) -> void:
	if _warming_up or not game.mobile_controls or args.is_empty():
		return
	var action := str(args[0])
	var payload: Variant = JSON.parse_string(str(args[1])) if args.size() > 1 else {}
	if not payload is Dictionary:
		return
	game.touch_input.handle(game,action,payload)
	_publish_mobile_state()

func _publish_mobile_state() -> void:
	if not game.mobile_controls:
		return
	var snapshot := {"state":game.state,"entryActive":game.entry_active,"bestiaryOpen":game.bestiary_open,"layoutMode":game.layout_mode,"ready":not _warming_up,"blocked":game.new_game_confirmation or game.rescue_result_visible or game.summary_visible}
	snapshot["canSketch"] = game.can_sketch()
	snapshot["sketchActive"] = game.sketch_active
	if preload("res://scripts/build_mode.gd").GM_ENABLED:
		snapshot["gmOpen"] = game.gm_menu_open
	var encoded := JSON.stringify(snapshot)
	if encoded == _mobile_state:
		return
	_mobile_state = encoded
	JavaScriptBridge.eval("window.tideMobileState="+encoded+";document.dispatchEvent(new Event('tide-mobile-state'));",true)

func _on_pointer_lock(_args: Array) -> void:
	if game.mobile_controls:
		return
	var document = JavaScriptBridge.get_interface("document")
	if document.pointerLockElement == null and game.state == "dive":
		game.toggle_pause()

func _on_visibility(_args: Array) -> void:
	if JavaScriptBridge.get_interface("document").hidden:
		if game.sketch_active:
			game.sketch_ui.end_stroke()
		_pause_active_game()

func _on_pause(_args: Array) -> void:
	_pause_active_game()

func _pause_active_game() -> void:
	game.touch_input.reset()
	if game.sketch_active:
		game.sketch_ui.end_stroke()
	if game.state in ["dive", "service"]:
		game.toggle_pause()

func _exit_tree() -> void:
	JavaScriptBridge.get_interface("window").tideMobileCommand = null
	var document = JavaScriptBridge.get_interface("document")
	document.removeEventListener("pointerlockchange", _lock_callback)
	document.removeEventListener("visibilitychange", _visibility_callback)
	document.removeEventListener("tide-pause", _pause_callback)
