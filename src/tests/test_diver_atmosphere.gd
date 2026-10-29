extends SceneTree
## Real GM switch callbacks and pooled exhalation lifecycle without player saves.
const Bubbles = preload("res://scripts/diver_bubbles.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1
var game: Node
var memory: MemoryProgression
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+description)

func _button(label: String) -> Button:
	for button: Button in game.hud.buttons:
		if button.text.begins_with(label):
			return button
	return null

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	await process_frame
	var before: Dictionary = memory._save_data().duplicate(true)
	_test_air_switch()
	await _test_bubbles()
	_check(memory._save_data() == before and memory.saves == 0,"GM testing and bubbles do not write progress or add saved cheat settings")
	_test_reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver GM air and breathing bubbles (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _test_air_switch() -> void:
	_check(not game.gm_infinite_air,"Infinite air starts disabled")
	game.toggle_gm_infinite_air()
	_check(not game.gm_infinite_air,"The switch requires the actual GM panel")
	game.open_gm_menu()
	var toggle: Button = _button("无限气瓶量")
	_check(toggle != null and toggle.text.ends_with("关闭"),"GM exposes an initially disabled air switch")
	if toggle == null:
		return
	toggle.pressed.emit()
	_check(game.gm_infinite_air and game.gm_menu_open and _button("无限气瓶量").text.ends_with("开启"),"Clicking enables the setting and updates the still-open panel")
	game.gm_select_dive_site(0,true)
	game.player.position = Vector3(0,-10,10)
	game.oxygen = 0.1
	game._update_dive(0.5)
	_check(game.state == "dive" and game.oxygen == memory.oxygen_max(),"Ordinary breathing cannot trigger rescue with infinite air on")
	game.hurt_cooldown = 0
	game.take_hunt_damage(12,true,"石头鱼")
	_check(game.oxygen == memory.oxygen_max() and game.poison_timer == 6.0 and game.hurt_flash > 0 and game.hunt_warning.contains("免除耗气"),"Touch damage retains poison and visible warning while removing the air cost")
	game._update_hunting_status(1.0)
	_check(game.oxygen == memory.oxygen_max() and game.poison_timer == 5.0,"Poison time advances without consuming infinite air")
	var hazard: Dictionary = game.hazards[0]
	var hazard_before: Vector3 = hazard.node.position
	hazard.node.position = game.player.position
	game.hurt_cooldown = 0
	game._update_dive(0.0)
	_check(game.oxygen == memory.oxygen_max() and game.notice.contains("免除耗气"),"Jellyfish contact also respects infinite air and explains it")
	hazard.node.position = hazard_before
	game.open_gm_menu()
	game.gm_select_dive_site(game.Ocean.site_index("amber_reef"),true)
	_check(game.gm_infinite_air and game.oxygen == memory.oxygen_max(),"Changing GM destinations retains the enabled switch")
	game.open_gm_menu()
	_button("无限气瓶量").pressed.emit()
	_check(not game.gm_infinite_air and _button("无限气瓶量").text.ends_with("关闭"),"Clicking again disables the same switch")
	game.close_gm_menu()
	game.poison_timer = 0
	game.hurt_cooldown = 0
	game.oxygen = 50
	game.take_hunt_damage(12,true,"石头鱼")
	game._update_hunting_status(1.0)
	_check(is_equal_approx(game.oxygen,36.5),"Disabling restores real contact damage and poison costs immediately")
	game.poison_timer = 0
	game.player.position = Vector3(0,-10,10)
	game._update_dive(0.5)
	_check(game.oxygen < 36.5,"Normal breathing resumes after disabling")
	game.open_gm_menu()
	_button("无限气瓶量").pressed.emit()
	game.close_gm_menu()

func _test_bubbles() -> void:
	var bubbles: Node3D = game.diver_bubbles
	game.player.position = Vector3(0,-10,10)
	game.player.rotation = Vector3.ZERO
	game.yaw = 0
	game.pitch = -0.12
	game.diver_motion.reset()
	bubbles.reset()
	_check(bubbles.batch.instance_count == 64 and bubbles.batch.visible_instance_count == 0,"Breathing starts with an empty, fixed-size shared mesh pool")
	var rig: Transform3D = game.player.get_child(0).global_transform
	bubbles.advance(0.5,rig,true,0.0,Vector3.ZERO)
	_check(bubbles.emitted_count == 0,"A breathing gap precedes the first exhalation")
	bubbles.advance(0.41,rig,true,0.0,Vector3.ZERO)
	_check(bubbles.emitted_count > 0 and not bubbles.particles.is_empty(),"A timed breath releases bubbles from the diver")
	var mouth: Vector3 = rig*Bubbles.REGULATOR
	var bubble: Dictionary = bubbles.particles[0]
	_check(bubble.position.y > mouth.y and Vector2(bubble.position.x-mouth.x,bubble.position.z-mouth.z).length() < 0.45,"Bubbles begin at the transformed regulator and rise in world space")
	var first_position: Vector3 = bubble.position
	for step in range(12):
		bubbles.advance(0.05,rig,true,0.0,Vector3.ZERO)
	var emitted: int = bubbles.emitted_count
	_check(emitted == 9 and bubble.position.y > first_position.y,"An idle exhalation contains nine staggered bubbles that rise")
	for step in range(12):
		bubbles.advance(0.05,rig,true,0.0,Vector3.ZERO)
	_check(bubbles.emitted_count == emitted,"The trail has a quiet inhalation gap instead of continuous emission")
	var saved: Array = bubbles.particles.duplicate(true)
	var timer: float = bubbles.breath_timer
	game.toggle_pause()
	game._physics_process(2.0)
	_check(bubbles.particles == saved and bubbles.breath_timer == timer,"Pausing freezes every bubble and the breathing cadence")
	game.open_gm_menu()
	game._physics_process(1.0)
	_check(bubbles.particles == saved,"GM menu also freezes the exhalation trail")
	game.gm_select_dive_site(0,true)
	_check(bubbles.particles.is_empty() and bubbles.batch.visible_instance_count == 0,"GM teleport clears bubbles from the previous location")
	game.player.position = Vector3(0,-10,10)
	for step in range(120):
		game._physics_process(1.0/60.0)
	_check(bubbles.emitted_count >= 9 and bubbles.batch.visible_instance_count > 0,"The actual diving physics loop emits the breathing art")
	var output: String = ProjectSettings.globalize_path("res://../.runtime/diver-atmosphere-checks")
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("breath-trail.png"))
	game.open_gm_menu()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("gm-infinite-air.png"))
	game.close_gm_menu()
	rig = game.player.get_child(0).global_transform
	for step in range(360):
		bubbles.advance(1.0/60.0,rig,false,0.0,Vector3.ZERO)
	_check(bubbles.particles.is_empty() and bubbles.batch.visible_instance_count == 0,"Finished bubbles expire without leaked instances")
	bubbles.reset()
	rig.origin.y = 2.0
	bubbles.advance(1.0,rig,true,1.0,Vector3.ZERO)
	_check(bubbles.emitted_count == 0,"No regulator bubbles spawn above the water")
	rig.origin.y = -0.6
	for step in range(180):
		bubbles.advance(1.0/60.0,rig,step < 90,0.0,Vector3.ZERO)
	var underwater := true
	for particle: Dictionary in bubbles.particles:
		underwater = underwater and particle.position.y < -0.15
	_check(underwater,"Bubbles disappear on reaching the surface")
	bubbles.reset()
	game.state = "dock"
	game.start_dive(true,false)
	game._physics_process(1.5)
	_check(bubbles.emitted_count == 0,"Boat entry keeps its splash separate from breathing bubbles")
	game.entry_active = false

func _test_reset() -> void:
	game.state = "paused"
	game.request_new_game()
	game.confirm_new_game()
	_check(not game.gm_infinite_air and game.diver_bubbles.particles.is_empty(),"Starting a new game resets the GM option and clears all bubbles")
