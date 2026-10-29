extends SceneTree
## Real depth lighting, neutral GPU samples and all shore-return lifecycle paths.
const Ocean = preload("res://scripts/ocean_config.gd")
const Lighting = preload("res://scripts/depth_lighting.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var memory: MemoryProgression
var reference: MeshInstance3D
var checks := 0
var failures := 0
var output: String
var rendered_luma: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	root.size = Vector2i(960, 600)
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
	output = ProjectSettings.globalize_path("res://../.runtime/depth-lighting-checks")
	DirAccess.make_dir_recursive_absolute(output)
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	_check(game.ocean_sun is DirectionalLight3D and game.diver_light is OmniLight3D, "The actual ocean exposes its directional sunlight and diver's local lamp")
	_check(_shore_is_reset(), "The initial dock starts with the original shore lighting and no visible diving lamp")
	game.start_dive(false, false)
	_test_depth_properties_and_ascent()
	_test_actual_camera_depth()
	_test_canyon_fill()
	await _test_neutral_gpu_luminance()
	_test_entry_and_gm_updates()
	await _test_pause_and_menu_freeze()
	_check(memory._save_data() == progress_before and memory.saves == 0, "Depth changes, rendered probes, entry, GM and pause never modify or save durable progress")
	_test_shore_restoration()
	var report := FileAccess.open(output.path_join("luminance.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify(rendered_luma, "  "))
		report.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver depth lighting (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_depth_properties_and_ascent() -> void:
	var snapshots: Array[Dictionary] = []
	for depth: float in [20.0, 50.0, 90.0]:
		_set_swim_camera_depth(depth)
		var actual_depth: float = maxf(0.0, -game.camera.global_position.y)
		_check(absf(actual_depth - depth) < 0.03 and _matches_profile(Lighting.profile(actual_depth,game.camera.global_position)), "A real %.0fm swimming camera immediately receives the corresponding global and local lighting" % depth)
		snapshots.append(_snapshot())
	_check(snapshots[0].ambient > snapshots[1].ambient and snapshots[1].ambient > snapshots[2].ambient, "Actual ambient illumination strictly decreases from twenty through fifty to ninety metres")
	_check(snapshots[0].sun > snapshots[1].sun and snapshots[1].sun > snapshots[2].sun, "Actual directional sunlight strictly decreases from shallow to deep water")
	_check(snapshots[0].fog > snapshots[1].fog and snapshots[1].fog > snapshots[2].fog, "Fog illumination fades with depth instead of keeping distant deep water bright")
	_check(_luma(snapshots[0].water) > _luma(snapshots[1].water) and _luma(snapshots[1].water) > _luma(snapshots[2].water), "The actual underwater background also becomes darker at each deeper sample")
	_check(game.diver_light.visible and game.diver_light.light_energy > 0 and game.diver_light.omni_range > 0 and game.diver_light.omni_range <= 12, "Deep water retains a visible local diving light with at most twelve metres of reach")
	_set_swim_camera_depth(20)
	_check(_snapshot() == snapshots[0], "Ascending to the original shallow camera depth restores the same lighting without residual darkness")

func _test_actual_camera_depth() -> void:
	var point := Vector3(Ocean.canyon_center_x(-325), -65, -325)
	game.player.position = point
	game.yaw = 0
	game.pitch = 0.8
	game._update_swim_camera()
	var deeper: Dictionary = _snapshot()
	var deeper_camera: float = -game.camera.global_position.y
	var deeper_matches: bool = _matches_profile(Lighting.profile(maxf(0.0, deeper_camera),game.camera.global_position))
	game.pitch = -0.8
	game._update_swim_camera()
	var shallower_camera: float = -game.camera.global_position.y
	_check(game.player.position == point and deeper_camera > shallower_camera + 5 and deeper.ambient < game.environment.ambient_light_energy and deeper_matches and _matches_profile(Lighting.profile(maxf(0.0, shallower_camera),game.camera.global_position)), "At unchanged diver depth, moving the following camera vertically changes lighting according to the actual camera position")

func _test_canyon_fill() -> void:
	var center := Vector3(Ocean.canyon_center_x(-325),-85,-325)
	var baseline: Dictionary = Lighting.profile(85)
	var local: Dictionary = Lighting.profile(85,center)
	_check(float(local.ambient_energy)>float(baseline.ambient_energy)+.1 and float(local.ambient_energy)<.3,"Canyon fill reveals nearby walls without washing out the deep-water mood")
	_check(Lighting.profile(85,Vector3(300,-85,300))==baseline and Lighting.profile(5,center)==Lighting.profile(5),"Canyon fill leaves other dive sites and surface lighting unchanged")
	var smooth_fade := true
	var previous: float = local.ambient_energy
	for offset in range(1,81):
		var sample: Dictionary = Lighting.profile(85,center+Vector3.RIGHT*offset)
		smooth_fade = smooth_fade and absf(float(sample.ambient_energy)-previous)<.015
		previous = sample.ambient_energy
	_check(smooth_fade and is_equal_approx(previous,float(baseline.ambient_energy)),"Canyon fill fades continuously back to the ocean lighting across the banks")

func _test_neutral_gpu_luminance() -> void:
	reference = MeshInstance3D.new()
	reference.name = "NeutralDepthLightingReference"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 3.0
	reference.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	material.metallic_specular = 0
	material.roughness = 1
	reference.material_override = material
	reference.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(reference)
	var hud_visible: bool = game.hud.visible
	game.hud.visible = false
	game.player.get_child(0).visible = false
	var values: Array[float] = []
	for depth: float in [20.0, 50.0, 90.0]:
		var value: float = await _render_reference(depth, false, 5.0, "neutral-%dm" % int(depth))
		values.append(value)
		rendered_luma[str(int(depth)) + "m_lamp_off"] = value
	_check(values[0] > values[1] * 1.08 and values[1] > values[2] * 1.08 and values[2] > 0.001, "The same neutral object's actual GPU luminance clearly decreases with depth, excluding all HUD pixels: %.4f / %.4f / %.4f" % values)
	var near_lit: float = await _render_reference(90, true, 5.0, "deep-near-lamp-on")
	rendered_luma["90m_near_lamp_on"] = near_lit
	_check(near_lit > values[2] + 0.015 and near_lit > 0.05, "The real local lamp keeps a nearby deep-water reference readable: unlit %.4f, lit %.4f" % [values[2], near_lit])
	var far_off: float = await _render_reference(90, false, 16.0, "deep-far-lamp-off")
	var far_on: float = await _render_reference(90, true, 16.0, "deep-far-lamp-on")
	rendered_luma["90m_far_lamp_off"] = far_off
	rendered_luma["90m_far_lamp_on"] = far_on
	_check(absf(far_on - far_off) < 0.005, "The diving lamp does not brighten a reference sixteen metres away: off %.4f, on %.4f" % [far_off, far_on])
	reference.free()
	game.hud.visible = hud_visible
	game.player.get_child(0).visible = true
	game.diver_light.visible = true

func _render_reference(depth: float, lamp_on: bool, distance: float, label: String) -> float:
	var point := Vector3(Ocean.canyon_center_x(-325), -depth, -320)
	game.player.position = point
	game.player.basis = Basis.IDENTITY
	game.camera.position = point
	reference.position = point + Vector3(0, 0, -distance)
	reference.scale = Vector3.ONE * distance / 5.0
	game.camera.look_at(reference.position)
	game._apply_underwater_lighting(depth)
	game.diver_light.visible = lamp_on
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	if frame.is_empty():
		_check(false, "The depth-luminance reference requires an actual GPU image")
		return 0.0
	frame.save_png(output.path_join(label + ".png"))
	var center: Vector2i = frame.get_size() / 2
	var total := 0.0
	var samples := 0
	for y in range(center.y - 32, center.y + 32, 2):
		for x in range(center.x - 32, center.x + 32, 2):
			total += _luma(frame.get_pixel(x, y))
			samples += 1
	return total / samples

func _test_entry_and_gm_updates() -> void:
	game.state = "dock"
	game.start_dive(true, false)
	_check(game.entry_active and _light_levels_match(Lighting.profile(0.0)), "Starting boat entry immediately clears the previous deep-water lighting")
	var bounded := true
	var continuous := true
	var previous: float = game.environment.ambient_light_energy
	for step in range(32):
		game._update_entry(0.1)
		var depth: float = maxf(0.0, -game.camera.global_position.y)
		var profile: Dictionary = Lighting.profile(depth,game.camera.global_position)
		var current: float = game.environment.ambient_light_energy
		bounded = bounded and current >= float(profile.ambient_energy) - 0.001 and current <= 0.381
		continuous = continuous and absf(current - previous) < 0.05
		previous = current
	_check(bounded and continuous and not game.entry_active and _matches_profile(Lighting.profile(maxf(0.0, -game.camera.global_position.y),game.camera.global_position)), "The complete entry camera blends smoothly into its measured underwater lighting and ends with the matching profile")
	for site: int in range(Ocean.DIVE_SITES.size()):
		game.open_gm_menu()
		game.gm_select_dive_site(site, true)
		var depth: float = maxf(0.0, -game.camera.global_position.y)
		_check(game.state == "dive" and not game.entry_active and _matches_profile(Lighting.profile(depth,game.camera.global_position)), "GM direct visit applies the actual camera's lighting before the next swimming frame at site %d" % site)

func _test_pause_and_menu_freeze() -> void:
	_set_swim_camera_depth(75)
	game.toggle_pause()
	var before: Dictionary = _snapshot()
	var camera_before: Transform3D = game.camera.transform
	await _physics_frames(15)
	_check(game.state == "paused" and _snapshot() == before and game.camera.transform == camera_before, "Pause freezes all actual depth-lighting properties and camera position in real physics frames")
	game.open_gm_menu()
	await _physics_frames(15)
	_check(game.gm_menu_open and _snapshot() == before and game.camera.transform == camera_before, "An open GM panel keeps deep-water illumination frozen")
	game.close_gm_menu()
	game.toggle_pause()

func _test_shore_restoration() -> void:
	_set_swim_camera_depth(90)
	game.finish_dive(false)
	_check(game.state == "dock" and _shore_is_reset(), "Normal return restores shore lighting immediately after a deep dive")
	game._apply_underwater_lighting(90)
	game.open_restaurant()
	_check(game.state == "restaurant" and _shore_is_reset() and not game.environment.fog_enabled, "Entering the restaurant clears any deep-water lighting while disabling underwater fog")
	game._apply_underwater_lighting(90)
	game.return_to_dock()
	_check(game.state == "dock" and _shore_is_reset() and game.environment.fog_enabled, "Returning from the restaurant restores the dock's normal light and fog settings")
	game.start_dive(false, false)
	_set_swim_camera_depth(90)
	var underwater: Dictionary = _snapshot()
	game.oxygen = 0
	game.finish_dive(true)
	_check(game.state == "rescuing" and _snapshot() == underwater, "The oxygen-depletion rescue transition holds the existing underwater lighting while the rescue overlay runs")
	game._physics_process(1.0)
	_check(game.state == "rescuing" and _snapshot() == underwater, "Deep-water lighting remains frozen during the rescue interval")
	game._physics_process(2.0)
	_check(game.state == "dock" and _shore_is_reset(), "Completing the rescue restores all shore lights before showing the dock result")
	game.dismiss_rescue_result()
	game.start_dive(false, false)
	_set_swim_camera_depth(90)
	game.toggle_pause()
	game.request_new_game()
	game.confirm_new_game()
	_check(game.state == "dock" and _shore_is_reset(), "Confirmed new game restores the original shore illumination and hides the diver lamp")

func _set_swim_camera_depth(depth: float) -> void:
	game.state = "dive"
	game.entry_active = false
	game.player.position = Vector3(Ocean.canyon_center_x(-325), -depth - 1.7, -325)
	game.player.velocity = Vector3.ZERO
	game.yaw = 0
	game.pitch = 0
	game._update_swim_camera()

func _matches_profile(profile: Dictionary) -> bool:
	return _light_levels_match(profile) and _color_close(game.environment.ambient_light_color, profile.ambient_color) and _color_close(game.ocean_sun.light_color, profile.sun_color) and _color_close(game.environment.fog_light_color, profile.water_color) and _color_close(game.diver_light.light_color, profile.lamp_color)

func _light_levels_match(profile: Dictionary) -> bool:
	return is_equal_approx(game.environment.ambient_light_energy, float(profile.ambient_energy)) and is_equal_approx(game.ocean_sun.light_energy, float(profile.sun_energy)) and is_equal_approx(game.environment.fog_light_energy, float(profile.fog_energy)) and is_equal_approx(game.diver_light.light_energy, float(profile.lamp_energy))

func _shore_is_reset() -> bool:
	var base: Dictionary = Lighting.profile(0.0)
	return is_equal_approx(game.environment.ambient_light_energy, 0.38) and is_equal_approx(game.ocean_sun.light_energy, 0.65) and is_equal_approx(game.environment.fog_light_energy, 0.85) and is_equal_approx(game.diver_light.light_energy, 0.35) and is_equal_approx(game.environment.fog_density, 0.0065) and not game.diver_light.visible and _color_close(game.environment.ambient_light_color, base.ambient_color) and _color_close(game.ocean_sun.light_color, base.sun_color) and _color_close(game.diver_light.light_color, base.lamp_color)

func _snapshot() -> Dictionary:
	return {"ambient":game.environment.ambient_light_energy,"ambient_color":game.environment.ambient_light_color,"sun":game.ocean_sun.light_energy,"sun_color":game.ocean_sun.light_color,"fog":game.environment.fog_light_energy,"fog_color":game.environment.fog_light_color,"fog_density":game.environment.fog_density,"water":game.environment.background_color,"lamp":game.diver_light.light_energy,"lamp_color":game.diver_light.light_color,"lamp_visible":game.diver_light.visible,"lamp_range":game.diver_light.omni_range}

func _color_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.001

func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func _physics_frames(count: int) -> void:
	game.set_physics_process(true)
	await physics_frame
	for step in range(count):
		await physics_frame
	game.set_physics_process(false)
