extends SceneTree
const Loot = preload("res://scripts/loot_catalog.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass
var checks := 0
var failures := 0
var game: Node

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func click_knife() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	game._unhandled_input(event)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	await physics_frame
	game.start_dive(false,false)
	var meadow: Node3D = game.reef_plants
	check(meadow.harvests.size()==592,"All visible grass and ribbon-algae sources across dive sites are registered")
	var plant: Dictionary = meadow.harvests[0]
	_isolate_plant(plant)
	var point: Vector3 = plant.position
	game.player.position = point+Vector3(0,1,1.5)
	game.yaw = 0
	game.pitch = -.6
	game._update_swim_camera()
	await physics_frame
	check(not meadow.target(game).is_empty(),"Normal third-person swim camera can aim at nearby grass by looking down")
	game.camera.position = point+Vector3(0,2,6)
	game.camera.look_at(point)
	await physics_frame
	check(meadow.target(game)==plant,"The close grass under the camera crosshair is targetable")
	check(game.context_hint().contains("右键"),"The nearby grass advertises the actual knife control")
	game.state = "paused"
	click_knife()
	check(plant.active and game.cargo.is_empty(),"Right click cannot harvest while paused")
	game.state = "dive"
	game.entry_active = true
	click_knife()
	check(plant.active and game.cargo.is_empty(),"Right click cannot harvest during entry")
	game.entry_active = false
	game.cargo = [{"id":"chest","name":"test","weight":game.progress.capacity(),"value":90}]
	click_knife()
	check(plant.active and game.capacity_warning_timer>0,"A full bag leaves the plant intact and displays the capacity warning")
	game.cargo.clear()
	game.diver_knife.reset()
	click_knife()
	check(not plant.active and game.cargo.size()==1 and game.cargo[0].id=="seagrass","A real right click cuts one grass clump and adds its canonical cargo")
	check(game.loot_feedback_title=="海草收割成功" and game.effects.size()>=8,"Harvest displays loot feedback, floating fragments and collection art")
	game.diver_motion.advance(.1,Vector3.ZERO,false)
	game.diver_knife.advance(game,.15)
	check(game.diver_knife.model.visible and absf(game.diver_knife.arm.rotation.y)>.4,"The diver actually swings the visible knife arm")
	var stump: Transform3D = plant.batch.get_instance_transform(plant.index)
	check(stump.basis.y.length()<plant.pose.basis.y.length()*.2,"The cut plant becomes a short visible stump")
	click_knife()
	check(game.cargo.size()==1 and not meadow.cut(plant),"Cooldown and harvested state prevent duplicate rewards")
	game.diver_knife.reset()
	game.player.position = point+Vector3(0,1,6)
	click_knife()
	check(game.cargo.size()==1,"The knife cannot harvest distant vegetation")
	game.player.position = point+Vector3(0,1,1.5)
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(15,8,.3)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = point+Vector3(0,1,.65)
	game.add_child(wall)
	meadow.reset_harvests()
	_isolate_plant(plant)
	await physics_frame
	check(meadow.target(game).is_empty(),"Scenery blocks cutting grass through walls")
	wall.queue_free()
	await physics_frame
	meadow.cut(plant)
	game.open_gm_menu()
	game.gm_select_dive_site(0)
	check(not plant.active,"GM relocation inside the current dive does not regrow harvested grass")
	game.finish_dive(false)
	check(game.progress.inventory.seagrass==1 and game.progress.total_fish==0,"Safe return stores grass without counting it as a fish")
	var saved: Dictionary = game.progress._save_data()
	var restored := MemoryProgression.new()
	restored._apply_save_data(saved)
	check(restored.inventory.seagrass==1 and restored.sell("seagrass",1)==16,"Grass survives save loading and sells at the canonical value")
	game.start_dive(false,false)
	check(plant.active and plant.batch.get_instance_transform(plant.index).is_equal_approx(plant.pose),"A new dive regrows the meadow and restores the full plant mesh")
	await _test_default_camera(plant)
	await _test_all_plant_sources()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("%s: Tide Diver knife and harvest (%d checks)." % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)

func _isolate_plant(selected: Dictionary) -> void:
	# Keep nearby clumps from masking a failed target or obstruction check.
	for plant: Dictionary in game.reef_plants.harvests:
		plant.active = plant == selected

func _test_default_camera(plant: Dictionary) -> void:
	var meadow: Node3D = game.reef_plants
	var old_root_target: Vector3 = plant.visual.to_global(plant.pose.origin)+Vector3.UP*.65
	for height: float in [1.5,2.0]:
		meadow.reset_harvests()
		_isolate_plant(plant)
		game.cargo.clear()
		game.diver_knife.reset()
		game.player.position = old_root_target+Vector3(0,height,1.6)
		game.yaw = 0
		game.pitch = -.12
		game._update_swim_camera()
		await physics_frame
		check(meadow.target(game)==plant,"Normal third-person pitch targets nearby grass without aiming at its root, height %.1f" % height)
		click_knife()
		check(not plant.active and game.cargo.size()==1,"Right-click harvest succeeds at the previously failing %.2f m default-camera pose" % sqrt(height*height+1.6*1.6))
	meadow.reset_harvests()
	_isolate_plant(plant)
	game.cargo.clear()
	game.diver_knife.reset()
	game.player.position = plant.position+Vector3(0,.5,-1.6)
	game.yaw = 0
	game.pitch = -.12
	game._update_swim_camera()
	await physics_frame
	click_knife()
	check(plant.active and game.cargo.is_empty(),"A plant behind the diver cannot be harvested by a forward knife swing")

func _source(plant: Dictionary) -> String:
	var path: String = str(plant.visual.get_path())
	if plant.index<0:
		return "ordinary grass"
	if path.contains("NaturalAtoll/LagoonGrass"):
		return "lagoon grass"
	if path.contains("NaturalAtoll/RibbonAlgae"):
		return "lagoon algae"
	if path.contains("ReefLife/"):
		return "site grass"
	if path.contains("DiveExpansions/"):
		return "exploration grass"
	if path.contains("ReefVegetation/RibbonAlgae"):
		return "reef algae"
	return "reef grass"

func _test_all_plant_sources() -> void:
	var meadow: Node3D = game.reef_plants
	var groups: Dictionary = {}
	for plant: Dictionary in meadow.harvests:
		var source: String = _source(plant)
		if not groups.has(source):
			groups[source] = []
		groups[source].append(plant)
	var expected := {"ordinary grass":89,"lagoon grass":90,"lagoon algae":30,"site grass":72,"exploration grass":76,"reef algae":65,"reef grass":170}
	for source: String in expected:
		check(groups.get(source,[]).size()==expected[source],"Registered every visible plant in source: "+source)
		var selected: Dictionary = {}
		for candidate: Dictionary in groups.get(source,[]):
			_isolate_plant(candidate)
			game.player.position = candidate.position+Vector3(0,1.2,1.6)
			game.yaw = 0
			game.pitch = -.12
			game._update_swim_camera()
			if meadow.target(game)==candidate:
				selected = candidate
				break
		check(not selected.is_empty(),"A reachable plant can be approached with the normal camera in source: "+source)
		if selected.is_empty():
			continue
		game.diver_knife.reset()
		game.cargo.clear()
		click_knife()
		check(not selected.active and game.cargo.size()==1 and game.cargo[0].id=="seagrass","Real right click harvests source: "+source)
		var stump: Transform3D = selected.batch.get_instance_transform(selected.index) if selected.index>=0 else selected.visual.transform
		check(stump.basis.y.length()<selected.pose.basis.y.length()*.2,"Harvest leaves a visible short stump in source: "+source)
		game.finish_dive(false)
		game.start_dive(false,false)
		var regrown: Transform3D = selected.batch.get_instance_transform(selected.index) if selected.index>=0 else selected.visual.transform
		check(selected.active and regrown.is_equal_approx(selected.pose),"A new dive restores the original plant geometry in source: "+source)
		await physics_frame
