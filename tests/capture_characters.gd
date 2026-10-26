extends SceneTree
## Actual asset closeups and actual game views; never loads or writes player saves.
const Person = preload("res://scripts/restaurant_person.gd")
const Diver = preload("res://scripts/diver_art.gd")
const Art = preload("res://scripts/furniture_art.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

var font := SystemFont.new()

func _init() -> void:
	call_deferred("_run")

func _save(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://artifacts/" + filename + ".png")
	if result != OK:
		printerr("Capture failed: " + filename)
		quit(1)
	print("Captured " + filename)

func _label(parent: Node, message: String, position: Vector2, size: int = 22) -> void:
	var label := Label.new()
	label.text = message
	label.position = position
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e8dfc6"))
	parent.add_child(label)

func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("173c43")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c4e3de")
	env.environment.ambient_light_energy = 0.40
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -145, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 35, 0)
	fill.light_energy = 0.25
	stage.add_child(fill)
	return stage

func _run() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	root.size = Vector2i(1600, 1000)
	await _people()
	await _diver()
	await _game()
	quit()

func _people() -> void:
	var stage: Node3D = _stage()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.8
	camera.position = Vector3(0, 2.9, -12)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.5, 0))
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	_label(layer, "潮汐湾 · 角色细节", Vector2(55, 35), 34)
	_label(layer, "游戏实际模型近景 / 主厨工作服 · 五种发型 · 衣领与缝线 · 分指手型", Vector2(55, 88), 20)
	var palette: Array[Color] = [Color("eadfc7"), Color("cc8b70"), Color("8ba99b"), Color("d7bc79"), Color("829cae"), Color("b78b98")]
	for i: int in range(6):
		var person := Person.new()
		person.setup(-1 if i == 0 else i - 1, palette[i], i == 0)
		person.position.x = (2.5 - i) * 1.14
		person.rotation.y = -0.17 if i % 2 == 0 else 0.17
		stage.add_child(person)
		person.reaction = "okay"
		person.reaction_age = 4
		person.advance(0.8)
		person._right_arm.rotation = Vector3(0.14, 0, 0.12)
		person._right_elbow.rotation.x = 0.15
		person._left_arm.rotation.x = 0.14
		person._left_elbow.rotation.x = 0.15
		person._bubble.hide()
		person._badge.hide()
		person._status.hide()
		Art._cylinder(stage, Vector3(person.position.x, -0.05, 0), 0.47, 0.09, Art._mat(Color("33575a")))
		var label_position: Vector2 = camera.unproject_position(Vector3(person.position.x, -0.2, 0))
		_label(layer, ["主厨", "侧分短发", "浅棕短发", "齐耳短发", "蓬松卷发", "盘发"][i], label_position + Vector2(-45, 10), 20)
	await _save("character_people_detail")
	stage.free()

func _diver() -> void:
	var stage: Node3D = _stage()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.2
	camera.position = Vector3(0, 5, -7)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	for i: int in range(2):
		var diver: Node3D = Diver.build()
		diver.position = Vector3(-1.8 if i == 0 else 1.8, 0, 0)
		diver.rotation.y = -0.40 if i == 0 else PI + 0.35
		stage.add_child(diver)
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	_label(layer, "潮汐湾 · 潜水员装备", Vector2(55, 35), 34)
	_label(layer, "游戏实际模型近景 / 分体面罩 · 呼吸软管 · 气瓶绑带 · 腕表 · 脚蹼与鱼枪", Vector2(55, 88), 20)
	await _save("character_diver_detail")
	stage.free()

func _game() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.start_dive()
	await physics_frame
	game._update_dive(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _save("character_dive_gameplay")
	game.finish_dive(false)
	for id in game.progress.RENOVATIONS:
		game.progress.renovation[id] = true
	game.progress.inventory.orange = 8
	game.open_restaurant()
	game.change_menu("orange", 4)
	game.start_service()
	game.service_spawn_time = 999
	for i: int in range(2):
		game._spawn_customer()
	game.cook_order(game.orders[0].id)
	game._physics_process(0.4)
	await _save("character_restaurant_gameplay")
	game.free()
