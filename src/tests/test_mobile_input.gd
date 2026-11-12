extends SceneTree
## Native game integration for the mobile command boundary; browser tests cover real fingers.
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void: pass
	func save_game() -> void: pass

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

func command(action: String, payload: Dictionary = {}) -> void:
	game.touch_input.handle(game,action,payload)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.mobile_controls = true
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	game.start_dive(false,false)
	await physics_frame
	game.player.position = Vector3(200,-12,200)
	game.camera.position = game.player.position+Vector3(0,.8,5)
	game.camera.look_at(game.player.position+Vector3(0,0,-10))
	check(game.state == "dive" and game._dive_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Mobile diving does not require a captured mouse")
	command("move",{"x":.4,"y":-.7})
	command("ascend",{"pressed":true})
	command("boost",{"pressed":true})
	check(game.touch_input.movement.is_equal_approx(Vector2(.4,-.7)) and game.touch_input.pressed("ascend") and game._swim_action_pressed("boost"), "Joystick, ascent, and boost coexist as independent touch inputs")
	var old_yaw: float = game.yaw
	var old_pitch: float = game.pitch
	command("look",{"dx":30,"dy":-20})
	check(game.yaw < old_yaw and game.pitch > old_pitch and not game.touch_input.movement.is_zero_approx(), "A second finger rotates the camera while the movement finger remains held")
	command("move",{"x":99,"y":-99})
	check(is_equal_approx(game.touch_input.movement.length(),1), "Diagonal or oversized touch motion is normalized to normal movement speed")
	command("move",{"x":NAN,"y":"bad"})
	command("look",{"dx":INF,"dy":NAN})
	check(game.touch_input.movement == Vector2.ZERO and is_finite(game.yaw) and is_finite(game.pitch), "Malformed or non-finite touch values never poison the camera or movement")
	command("move",{"x":0,"y":-1})
	var before: Vector3 = game.player.position
	await physics_frame
	game._update_dive(1.0/60.0)
	check(game.player.position.distance_to(before) > .01 and game.player.position.y > before.y, "Combined joystick and ascent move the actual physics body")
	command("ascend",{"pressed":false})
	check(not game.touch_input.pressed("ascend") and game.touch_input.pressed("boost") and game.touch_input.movement.y == -1, "Releasing ascent preserves independent joystick and boost fingers")
	command("release")
	check(game.touch_input.movement == Vector2.ZERO and game.touch_input.held.is_empty(), "A cancellation releases every touch control without synthetic keyboard state")
	game._clear_projectiles()
	game.shot_cooldown = 0
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	game._unhandled_input(mouse)
	check(game.projectiles.is_empty() and game.shot_cooldown == 0, "A browser-emulated mouse click cannot fire a second harpoon on mobile")
	command("shoot")
	check(game.projectiles.size() == 1 and game.shot_cooldown > 0, "The touch fire command launches the real harpoon exactly once")
	command("shoot")
	check(game.projectiles.size() == 1, "The regular weapon cooldown also applies to touch firing")
	command("knife")
	check(game.diver_knife.remaining > 0, "The touch knife action starts the real harvest swing")
	command("move",{"x":1,"y":0})
	command("descend",{"pressed":true})
	command("pause")
	check(game.state == "paused" and game.touch_input.movement == Vector2.ZERO and game.touch_input.held.is_empty(), "Pausing clears held touch controls immediately")
	command("move",{"x":1,"y":0})
	command("shoot")
	check(game.touch_input.movement == Vector2.ZERO and game.projectiles.size() == 1, "Paused games reject movement and firing commands")
	command("pause")
	check(game.state == "dive" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Mobile resume returns to swimming without requesting pointer lock")
	command("move",{"x":0,"y":-1})
	command("bestiary")
	check(game.bestiary_open and game.touch_input.movement == Vector2.ZERO, "Opening the journal from the touch bar releases the joystick")
	command("bestiary")
	check(not game.bestiary_open and game.state == "dive", "The touch journal toggle resumes the prior swimming state")
	game.entry_active = true
	game._clear_projectiles()
	game.shot_cooldown = 0
	command("move",{"x":1,"y":1})
	command("shoot")
	check(game.touch_input.movement == Vector2.ZERO and game.projectiles.is_empty(), "Entry animation rejects movement and weapon touches")
	game.entry_active = false
	command("move",{"x":1,"y":0})
	command("boost",{"pressed":true})
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.touch_input.movement == Vector2.ZERO and game.touch_input.held.is_empty(), "Losing application focus clears held movement and boost")
	game.state = "dive"
	game.player.position.y = -2
	command("interact")
	check(game.state == "dock", "The touch interact action returns from the surface through normal dive settlement")
	game.mobile_controls = false
	command("move",{"x":1,"y":0})
	check(game.touch_input.movement == Vector2.ZERO and game._dive_mouse_mode() == Input.MOUSE_MODE_CAPTURED, "Desktop games ignore mobile commands and retain mouse-capture controls")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver mobile input (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
