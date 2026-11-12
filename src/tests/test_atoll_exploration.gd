extends SceneTree
const DiveFixture = preload("res://tests/dive_fixture.gd")
## Real local encounters: hunt, collect, refill and cut the new atoll garden.
const Ocean = preload("res://scripts/ocean_config.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	game.start_dive(false,false)
	await physics_frame
	var added_fish: Array = game.fish.filter(func(item: Dictionary)->bool: return item.get("atoll_activity",false))
	# This suite isolates unbanked cargo; the separate bestiary suite covers first-discovery rewards.
	if not added_fish.is_empty():
		var known_id: String = game.FishData.SPECIES[added_fish[0].kind].id
		game.progress.discoveries[known_id] = {"method":"caught","seen":true}
	var original: Dictionary = game.progress._save_data().duplicate(true)
	var activity: Node3D = game.ocean_root.get_node_or_null("AtollActivities")
	check(activity!=null,"The actual ocean contains the three atoll activity beds")
	if activity!=null:
		check(activity.get_child_count()==3 and activity.get_meta("draw_batches")==6 and activity.find_children("*","CollisionObject3D",true,false).is_empty(),"Three visual activities share six batches and leave the swim route unobstructed")
	check(added_fish.size()==12,"Twelve new huntable residents are added through the actual fish spawner")
	var kinds := {}
	var homes_clear := true
	var spread := true
	for index in range(added_fish.size()):
		var fish: Dictionary = added_fish[index]
		kinds[fish.kind] = true
		homes_clear = homes_clear and game._open_water(fish.home,float(game.FishData.SPECIES[fish.kind].radius)) and fish.home.distance_to(Ocean.ZONES[4].center)<95
		for other in range(index):
			spread = spread and (fish.home as Vector3).distance_to(added_fish[other].home)>8.0
	check(kinds.size()>=7 and homes_clear and spread,"Different catchable species occupy separated, physically clear atoll homes")
	if not added_fish.is_empty():
		var target: Dictionary = added_fish[0]
		game.cargo.clear()
		game._hit_fish(target,99)
		check(not target.alive and game.cargo.size()==1 and game.cargo[0].id==game.FishData.SPECIES[target.kind].id,"A new atoll resident can actually be caught into the player's bag")
	var names: Array = Ocean.atoll_activity_points().map(func(point: Dictionary)->String: return point.name)
	var resources: Array = game.pickups.filter(func(item: Dictionary)->bool: return item.get("location_name","") in names)
	check(resources.size()==6,"The activity loop contains six real collectible and refill resources")
	for point: Dictionary in Ocean.atoll_activity_points():
		game.player.position = point.position+Vector3.UP*4
		check(game.nearby_exploration_point().get("name","")==point.name,"The navigation HUD recognizes "+str(point.name))
	for item: Dictionary in resources:
		game.cargo.clear()
		game.oxygen = 30
		game.player.position = item.node.position
		await physics_frame
		check(game.nearest_pickup()==item,"The diver can reach "+str(item.location_name)+" / "+str(item.kind))
		game.interact()
		if item.kind=="oxygen":
			check(game.oxygen>30 and not item.active,"The outer sandbar air bottle refills the real air gauge")
		elif item.kind=="chest":
			check(item.get("loot_opened",false) and (not game.cargo.is_empty() or game.oxygen>30),"The sandbar treasure opens and grants its normal randomized rewards")
		else:
			check(not item.active and game.cargo.size()==1 and game.cargo[0].id==item.kind,"The new "+str(item.kind)+" is collected through the real interaction system")
	var plants: Array = game.reef_plants.harvests.filter(func(plant: Dictionary)->bool: return str(plant.visual.get_path()).contains("AtollActivities/SeagrassGarden/"))
	check(plants.size()==40,"All forty garden plants register with the existing knife harvest system")
	game.cargo.clear()
	game.diver_knife.reset()
	var found := false
	for plant: Dictionary in plants:
		game.player.position = plant.position+Vector3(0,1,1.5)
		game.yaw = 0
		game.pitch = -.2
		game._update_swim_camera()
		await physics_frame
		var selected: Dictionary = game.reef_plants.target(game)
		if selected.is_empty() or not plants.has(selected):
			continue
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		game._unhandled_input(event)
		found = not selected.active and game.cargo.size()==1 and game.cargo[0].id=="seagrass"
		break
	check(found,"A real right click in the new garden harvests sea grass")
	DiveFixture.visit(game,Ocean.site_index("pearl_atoll"),true)
	check(plants.any(func(plant: Dictionary)->bool: return not plant.active),"Test relocation during a dive does not regenerate the harvested garden")
	check(game.progress._save_data()==original,"Unbanked exploration and collection do not mutate durable progression")
	game.finish_dive(false)
	check(game.progress.inventory.seagrass==1,"Returning safely banks the harvested garden sea grass")
	game.start_dive(false,false)
	check(plants.all(func(plant: Dictionary)->bool: return plant.active),"A fresh dive regrows the garden")
	if "--capture-atoll" in OS.get_cmdline_user_args():
		await _capture()
	game.free()
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("%s: Tide Diver atoll activities (%d checks)." % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)

func _capture() -> void:
	root.size = Vector2i(1440,900)
	game.hud.visible = false
	game.player.visible = false
	for index in range(3):
		var point: Vector3 = Ocean.atoll_activity_points()[index].position
		game.camera.position = point+Vector3(10,10,12)
		game.camera.look_at(point+Vector3.UP)
		game._animate_ocean(0)
		game._apply_underwater_lighting(maxf(0,-game.camera.position.y))
		await process_frame
		await RenderingServer.frame_post_draw
		var file: String = "user://atoll-activity-%d.png" % index
		check(root.get_texture().get_image().save_png(file)==OK,"Capture activity %d" % index)
