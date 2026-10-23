extends SceneTree
## Reproducible visual review of actual models and UI; no player saves are loaded or written.
const Art = preload("res://scripts/fish_art.gd")
const FishData = preload("res://scripts/fish_catalog.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

var font := SystemFont.new()

func _init() -> void:
	call_deferred("_run")

func _label(parent: Node, text: String, point: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)

func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://artifacts/"+name+".png")
	if error != OK:
		printerr("Capture failed: "+name)
		quit(1)
	print("Captured "+name)

func _run() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	root.size = Vector2i(1440,900)
	if "--gallery" in OS.get_cmdline_user_args():
		await _gallery()
	else:
		await _gameplay()
	quit()

func _gallery() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0c2835")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c7e9e1")
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-25,0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	camera.position = Vector3(0,0,30)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	_label(layer,"潮汐湾 · 九种海鱼",Vector2(55,22),30,Color("e9f5ec"))
	_label(layer,"TIDE DIVER  /  原创低多边形模型  /  实际游戏资产",Vector2(55,67),15,Color("91b9bc"))
	for kind in range(9):
		var fish := Art.build(kind)
		fish.position = Vector3((kind%3-1)*9.6,4.6-float(kind/3)*5.6,0)
		fish.rotation = Vector3(0.12,2.0,0)
		fish.scale = Vector3.ONE*1.5
		world.add_child(fish)
		var point: Vector2 = camera.unproject_position(fish.position)
		var data: Dictionary = FishData.SPECIES[kind]
		_label(layer,"%02d  %s" % [kind+1,data.name],point+Vector2(-184,72),21,Color("e9f5ec"))
		_label(layer,"%d G  ·  %d kg  ·  耐久 %d" % [data.value,data.weight,data.hp],point+Vector2(-184,105),15,Color("f5c779"))
	await _save("fish_catalog")
	world.free()

func _gameplay() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.start_dive()
	await physics_frame
	for item in game.fish:
		item.alive = false
		item.node.visible = false
	game.player.position = Vector3(200,-25,200)
	game._update_dive(0.0)
	for kind: int in [4,5,8]:
		for item in game.fish:
			if item.kind != kind:
				continue
			item.alive = true
			item.node.visible = true
			item.node.position = game.player.position+Vector3(0,0,-10) if kind == 8 else game.player.position+Vector3(-4 if kind == 4 else 4,0,-8)
			item.home = item.node.position
			game._update_fish(item,0.1)
			break
	game.camera.position = Vector3(200,-22,208)
	game.camera.look_at(Vector3(200,-25,190))
	game.poison_timer = 4.8
	game.oxygen = 23.0
	game.hud.queue_redraw()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _save("hunting_hud")
	game.finish_dive(false)
	for species in FishData.SPECIES:
		game.progress.inventory[species.id] = 2
	game.open_restaurant()
	game.hud.restaurant_ui._change_warehouse_page(1)
	game._physics_process(0.0)
	await _save("warehouse_new_fish")
	game.free()
