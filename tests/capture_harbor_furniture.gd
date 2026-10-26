extends SceneTree
## Actual furniture assets and shop previews, using isolated memory progression.
const Art = preload("res://scripts/furniture_art.gd")
const Rules = preload("res://scripts/layout_rules.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

var font := SystemFont.new()
var failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _label(parent: Node, value: String, pos: Vector2, size: int, color: Color = Color("e3dbc4")) -> void:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _save(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://artifacts/" + filename + ".png")
	failed = failed or error != OK
	print("Captured " + filename if error == OK else "FAIL: " + filename)

func _run() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = Vector2i(1600, 1000)
	var groups: Array = [["table", "plant"], ["rug", "lamp"], ["shelf", "bench"], ["parasol", "coastal"]]
	for i: int in range(groups.size()):
		await _gallery(groups[i], i + 1)
	await _game()
	quit(1 if failed else 0)

func _gallery(kinds: Array, page: int) -> void:
	var ui := Control.new()
	root.add_child(ui)
	var background := ColorRect.new()
	background.color = Color("12343c")
	background.size = Vector2(1600, 1000)
	ui.add_child(background)
	_label(ui, "潮间食堂 · 渔港家具", Vector2(48, 30), 34)
	_label(ui, "实际游戏模型  /  浅木 · 藤编 · 哑光灰蓝 · 编织细节  /  %02d" % page, Vector2(50, 83), 20, Color("9db9b8"))
	for row: int in range(2):
		var kind: String = kinds[row]
		for column: int in range(3):
			var variant: String = ["basic", "comfort", "premium"][column]
			var origin := Vector2(42 + column * 510, 140 + row * 420)
			var panel := ColorRect.new()
			panel.color = Color("1b424a")
			panel.position = origin
			panel.size = Vector2(496, 398)
			ui.add_child(panel)
			var container := SubViewportContainer.new()
			container.position = origin + Vector2(8, 8)
			container.size = Vector2(480, 298)
			ui.add_child(container)
			var viewport := SubViewport.new()
			viewport.size = Vector2i(480, 298)
			viewport.own_world_3d = true
			viewport.transparent_bg = true
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			container.add_child(viewport)
			var model: Node3D = Art.build({"kind":kind, "variant":variant, "uid":100, "color":0})
			viewport.add_child(model)
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color("c0d5dc")
			environment.environment.ambient_light_energy = 0.55
			environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			viewport.add_child(environment)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-42, -28, 0)
			sun.light_energy = 0.85
			viewport.add_child(sun)
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 4.0 if kind in ["table", "parasol", "rug"] else (2.6 if kind in ["shelf", "lamp"] else 2.0)
			camera.position = Vector3(3, 4.8 if kind == "rug" else 2.7, 5)
			viewport.add_child(camera)
			camera.look_at(Vector3(0, 0.1 if kind == "rug" else (1.30 if kind == "parasol" else (0.96 if kind in ["shelf", "lamp"] else 0.7)), 0))
			var data: Dictionary = Rules.variant_data(kind, variant)
			_label(ui, data.name, origin + Vector2(22, 311), 25)
			_label(ui, "%s · %d G" % [["基础款", "舒适款", "精品款"][column], data.cost], origin + Vector2(23, 354), 19, Color("d9b57c"))
	await _save("harbor_furniture_%d" % page)
	ui.free()

func _game() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	for id: String in game.progress.RENOVATIONS:
		game.progress.renovation[id] = true
	game.progress.coins = 12000
	game.open_restaurant()
	game.enter_layout()
	for item: Dictionary in game.layout_work.furniture_items():
		item.placed = false
	var placements: Array = [["table","basic",-3.5,0.0],["table","comfort",3.5,0.0],["table","premium",3.5,4.5],["shelf","premium",8,1.0],["bench","premium",-7,5.5],["parasol","premium",-7,8.0],["plant","premium",-8.5,2],["lamp","premium",7,5.5],["coastal","basic",-2,7],["coastal","comfort",7,7],["coastal","premium",4,8],["rug","premium",3.5,4.5]]
	for placement: Array in placements:
		game.buy_layout_furniture(placement[0], placement[1])
		if not game.place_layout_at(placement[2], placement[3]):
			printerr("FAIL: gallery placement " + str(placement))
			failed = true
	game.save_layout()
	game._physics_process(0)
	game.hud.visible = false
	game.camera.position = game.restaurant_node.position + Vector3(21, 17, 28)
	game.camera.look_at(game.restaurant_node.position + Vector3(0, 0, 2))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _save("harbor_restaurant")
	game.hud.visible = true
	game.enter_layout()
	for kind: String in Rules.CATALOG:
		game.hud.restaurant_ui.layout_ui.set_category(kind)
		game._physics_process(0)
		await _save("harbor_shop_" + kind)
	game.layout_panel_visible = false
	game.layout_zoom = 19
	game.layout_camera_yaw = -0.75
	game.layout_camera_pitch = deg_to_rad(38)
	game.hud.rebuild()
	game._physics_process(0)
	await _save("harbor_layout_orbit")
	game.free()
