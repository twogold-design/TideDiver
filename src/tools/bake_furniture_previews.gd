extends SceneTree
## Bake the shop's static views from the actual models, using its original lighting.
const Furniture = preload("res://scripts/furniture_art.gd")
const Rules = preload("res://scripts/layout_rules.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var directory := "res://assets/furniture_previews/"
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(232,248)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c0d5dc")
	world.environment.ambient_light_energy = 0.65
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42,-28,0)
	light.light_energy = 1.1
	scene.add_child(light)
	var view := Camera3D.new()
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(view)
	view.current = true
	var count := 0
	for kind: String in Rules.CATALOG:
		for variant: String in Rules.variant_ids(kind):
			var furniture := Furniture.build({"kind":kind,"variant":variant,"uid":-1,"color":0})
			scene.add_child(furniture)
			view.size = 4.4 if kind in ["table","rug","parasol","soft"] else (3.4 if kind == "bench" else 2.8)
			var position := Vector3(4,5,6) if kind == "rug" else Vector3(4,3,6)
			view.look_at_from_position(position,Vector3(0,0.15 if kind == "rug" else (1.5 if kind == "soft" else 0.85),0))
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var result := viewport.get_texture().get_image().save_png(directory+kind+"_"+variant+".png")
			if result != OK:
				push_error("Could not bake furniture preview: "+kind+"/"+variant)
				quit(1)
				return
			furniture.free()
			count += 1
	viewport.free()
	print("Baked %d furniture previews." % count)
	quit()
