extends SceneTree
## Ordered drawing, pointer inputs, responsive layouts and real dive lifecycle.
const Catalog = preload("res://scripts/wildlife_catalog.gd")
const Sketch = preload("res://scripts/wildlife_sketch.gd")
const WATER := Vector3(200,-12,200)
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void: pass
	func save_game() -> void: pass
var checks := 0
var failures := 0
var signals := 0
var ui: Control
var game: Node

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+description)

func _trace(panel: Control, reverse := false, from := 0, to := -1, pointer := "api") -> void:
	var points: PackedVector2Array = panel.contour_points()
	if reverse:
		points.reverse()
	var stop: int = points.size() if to < 0 else mini(to,points.size())
	if pointer == "api":
		panel.begin_stroke(points[from])
	else:
		_pointer(panel,pointer,points[from],true,true)
	for index in range(from+1,stop):
		if pointer == "api":
			panel.continue_stroke(points[index])
		else:
			_pointer(panel,pointer,points[index],false,true)
	if pointer == "api":
		panel.end_stroke()
	else:
		_pointer(panel,pointer,points[stop-1],true,false)

func _pointer(panel: Control, kind: String, point: Vector2, button: bool, pressed: bool) -> void:
	var event: InputEvent
	if kind == "touch":
		if button:
			event = InputEventScreenTouch.new()
			event.pressed = pressed
		else:
			event = InputEventScreenDrag.new()
		event.index = 2
	else:
		if button:
			event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
		else:
			event = InputEventMouseMotion.new()
			event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	panel._gui_input(event)

func _run() -> void:
	root.size = Vector2i(1440,900)
	ui = Sketch.new()
	root.add_child(ui)
	ui.completed.connect(func(_id: String) -> void: signals += 1)
	await process_frame
	var signatures := {}
	for record: Dictionary in Catalog.entries():
		ui.close_panel()
		ui.open_entry(record.id)
		if record.catchable:
			_check(not ui.active,"Catchable species cannot open drawing: "+record.id)
			continue
		var points: PackedVector2Array = ui.contour_points()
		_check(points.size() > 20 and points[0].is_equal_approx(points[-1]),"Closed detailed outline: "+record.id)
		var signature := str(points)
		_check(not signatures.has(signature),"Distinct species outline: "+record.id)
		signatures[signature] = true
		_trace(ui)
		_check(ui.trace_complete and ui.completion_ratio() >= .95,"Clockwise outline can finish: "+record.id)
		ui.restart()
		_trace(ui,true)
		_check(ui.trace_complete,"Counterclockwise outline can finish: "+record.id)
	_check(signals == 0,"Tracing waits for explicit continue gesture before leaving the drawing")
	ui.open_entry("sand_ray")
	var points: PackedVector2Array = ui.contour_points()
	ui.begin_stroke(points[0])
	ui.end_stroke()
	_check(ui.completion_ratio() == 0 and not ui.trace_complete,"A tap cannot complete an outline")
	ui.begin_stroke(Vector2(1,1))
	ui.continue_stroke(points[points.size()/2])
	ui.end_stroke()
	_check(ui.completion_ratio() == 0,"Off-canvas scribbling cannot earn progress")
	ui.begin_stroke(points[0])
	ui.continue_stroke(points[points.size()/2])
	ui.end_stroke()
	_check(ui.completion_ratio() < .2 and not ui.trace_complete,"A shortcut across the silhouette cannot complete it")
	ui.restart()
	var middle: int = points.size()/2
	_trace(ui,false,0,middle)
	var partial: float = ui.completion_ratio()
	_check(partial > .3 and partial < .7,"A partial continuous stroke earns proportional progress")
	ui.begin_stroke(points[0])
	ui.continue_stroke(points[1])
	ui.end_stroke()
	_check(is_equal_approx(ui.completion_ratio(),partial),"Restarting at an unrelated outline point earns no progress")
	_trace(ui,false,middle-1)
	_check(ui.trace_complete,"Lifting and resuming from the endpoint can finish")
	ui.restart()
	_check(ui.completion_ratio() == 0 and not ui.trace_complete,"Restart clears all drawing progress")
	for dimensions: Vector2i in [Vector2i(938,480),Vector2i(667,300)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		ui.open_entry("reef_butterfly")
		points = ui.contour_points()
		var bounds: Rect2 = ui.get_viewport_rect()
		for child in ui.get_children():
			if child is Button:
				_check(bounds.encloses(child.get_rect()),"Drawing buttons remain on-screen at "+str(dimensions))
		for kind in ["mouse","touch"]:
			ui.restart()
			_trace(ui,false,0,-1,kind)
			_check(ui.trace_complete,kind+" drawing completes on small screen "+str(dimensions))
	ui.open_entry("sand_ray")
	points = ui.contour_points()
	middle = points.size()/2
	_trace(ui,false,0,middle)
	partial = ui.completion_ratio()
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	await process_frame
	_check(is_equal_approx(ui.completion_ratio(),partial),"Resizing preserves existing normalized drawing progress")
	_trace(ui,false,middle-1)
	_check(ui.trace_complete,"Drawing resumes on resized outline")
	ui.free()
	await _test_gameplay()
	game.free()
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("%s: Tide Diver wildlife sketch (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _test_gameplay() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	game.start_dive(false,false)
	await physics_frame
	game.entry_active = false
	game.player.position = WATER
	game.player.velocity = Vector3.ZERO
	for item: Dictionary in game.fish:
		item.node.hide()
	game.reef_fish.hide()
	game.marine_life.hide()
	game.canyon_shark.hide()
	game.crevice_habitat.hide()
	game.ray_habitat.show()
	for record: Dictionary in game.ray_habitat.rays:
		record.node.hide()
	var ray: Node3D = game.ray_habitat.rays[0].node
	ray.global_position = WATER+Vector3(0,0,-10)
	ray.show()
	game.camera.position = WATER+Vector3(0,.8,5)
	game.camera.look_at(ray.global_position,Vector3.UP)
	game.wildlife_observation.advance(game,.2)
	_check(game.can_sketch(),"A real visible ray offers the sketch action")
	var catchable: Dictionary = game._add_fish(0,WATER+Vector3(0,0,-8))
	catchable.node.global_position = WATER+Vector3(0,0,-8)
	game.camera.look_at(catchable.node.to_global(catchable.node.get_meta("harpoon_center",Vector3.ZERO)),Vector3.UP)
	game.wildlife_observation.advance(game,.2)
	_check(game.can_sketch() and game.target_fish().get("node") == catchable.node,"A catchable fish and ornamental sketch candidate can overlap in view")
	game.shot_cooldown = 0
	var projectile_count: int = game.projectiles.size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._unhandled_input(click)
	_check(not game.sketch_active and game.state == "dive" and game.projectiles.size() == projectile_count+1,"Aimed catchable fish keeps left-click harpoon priority over nearby sketch wildlife")
	catchable.alive = false
	catchable.node.hide()
	game._clear_projectiles()
	game.camera.look_at(ray.global_position,Vector3.UP)
	game.wildlife_observation.advance(game,.2)
	game.begin_sketch()
	_check(game.sketch_active and game.state == "sketch" and game.sketch_ui.active,"Sketch opens its modal and changes dive state")
	game._on_sketch_completed("sand_ray")
	_check(not game.progress.has_discovery("sand_ray") and game.sketch_active,"Forged completion cannot unlock an unfinished outline")
	var air: float = game.oxygen
	var location: Vector3 = game.player.position
	var animal_location: Vector3 = ray.global_position
	var coins: int = game.progress.coins
	game._physics_process(10.0)
	_check(game.oxygen == air and game.player.position == location and ray.global_position == animal_location,"Drawing freezes oxygen, player and wildlife simulation")
	game.open_bestiary()
	_check(not game.bestiary_open and game.state == "sketch","Journal cannot interrupt a drawing")
	game.cancel_sketch()
	_check(not game.sketch_active and game.state == "dive" and not game.progress.has_discovery("sand_ray"),"Cancel returns to dive without unlocking")
	game._on_sketch_completed("sand_ray")
	_check(game.progress.coins == coins and not game.progress.has_discovery("sand_ray"),"A late completion after cancellation cannot grant a reward")
	game.wildlife_observation.advance(game,.2)
	game.begin_sketch()
	_trace(game.sketch_ui)
	_check(game.sketch_ui.trace_complete and game.state == "sketch" and not game.progress.has_discovery("sand_ray"),"Completed outline waits for the explicit continue gesture")
	game.sketch_ui.confirm_completion()
	_check(game.state == "dive" and not game.sketch_active and game.progress.has_discovery("sand_ray"),"Continue unlocks the drawn animal and resumes the same dive")
	_check(game.progress.discoveries.get("sand_ray",{}).get("method","") == "sketched" and game.progress.coins-coins == Catalog.entry("sand_ray").reward and game.cargo.is_empty(),"Sketch gives exactly the catalog reward without capture cargo")
	game.sketch_ui.confirm_completion()
	game._on_sketch_completed("sand_ray")
	game.wildlife_observation.advance(game,.2)
	_check(game.progress.coins-coins == Catalog.entry("sand_ray").reward and not game.can_sketch(),"Duplicate completion cannot reward or sketch an already discovered species")
	for exit_method in ["escape","pause"]:
		# Reset just this discovery to exercise another real completion lifecycle.
		game.progress.discoveries.erase("sand_ray")
		game.wildlife_observation.advance(game,.2)
		game.begin_sketch()
		_trace(game.sketch_ui)
		coins = game.progress.coins
		if exit_method == "escape":
			var escape := InputEventKey.new()
			escape.physical_keycode = KEY_ESCAPE
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
			await process_frame
			await process_frame
			var release := InputEventKey.new()
			release.physical_keycode = KEY_ESCAPE
			release.keycode = KEY_ESCAPE
			Input.parse_input_event(release)
			await process_frame
			await process_frame
		else:
			game.toggle_pause()
		_check(not game.sketch_active and game.state == ("dive" if exit_method == "escape" else "paused"),"Completed drawing leaves correctly through "+exit_method)
		_check(game.progress.has_discovery("sand_ray") and game.progress.coins-coins == Catalog.entry("sand_ray").reward,"Completed drawing retains its discovery and reward when exiting through "+exit_method)
		game.cancel_sketch()
		game._on_sketch_completed("sand_ray")
		_check(game.progress.coins-coins == Catalog.entry("sand_ray").reward,"Repeated callbacks after "+exit_method+" cannot pay twice")
		if game.state == "paused":
			game.toggle_pause()
