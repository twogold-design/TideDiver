extends SceneTree
## Exercise the giant encounter through the real dive lifecycle, without saves.
const Ocean = preload("res://scripts/ocean_config.gd")
const Shark = preload("res://scripts/whale_shark.gd")
const DiveFixture = preload("res://tests/dive_fixture.gd")
const Catalog = preload("res://scripts/wildlife_catalog.gd")
var checks := 0
var failures := 0

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+description)

func visual_pose(animal: Node3D) -> Array:
	var pose: Array = [animal.transform]
	for node: Node3D in animal.find_children("*", "Node3D", true, false):
		pose.append(node.transform)
		if node.has_meta("skin_material"):
			pose.append(node.get_meta("skin_material").get_shader_parameter("swim_clock"))
	return pose

func corners(box: AABB) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x: float in [0.0, 1.0]:
		for y: float in [0.0, 1.0]:
			for z: float in [0.0, 1.0]:
				result.append(box.position+box.size*Vector3(x,y,z))
	return result

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var memory := MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	game.start_dive(false, false)
	await physics_frame
	var whale: Node3D = game.whale_shark
	check(is_instance_valid(whale), "The real ocean includes the giant whale shark")
	if not is_instance_valid(whale):
		game.free()
		quit(1)
		return
	var instance_id: int = whale.get_instance_id()
	var existing_fish: int = game.fish.size()
	var existing_hazards: int = game.hazards.size()
	var before: Dictionary = memory._save_data().duplicate(true)
	var record: Dictionary = Catalog.entry("whale_shark")
	check(not record.is_empty() and not record.get("catchable", true) and int(record.get("reward",0)) == 120, "Whale shark is an ornamental sketch discovery with its own reward")
	var all_present := true
	var phases: Dictionary = {}
	for seed_value in range(32):
		all_present = whale.begin_dive(seed_value) and all_present
		phases[whale.phase_offset] = true
	check(all_present and whale.spawned, "Each dive has its one whale shark, without failed encounter rolls")
	check(phases.size() > 24, "Dive seeds vary the giant's patrol phase")
	whale.begin_dive(128)
	var phase: float = whale.phase_offset
	whale.animate(20.0, Vector3(35,-70,-360))
	var first_pose: Array = visual_pose(whale)
	whale.begin_dive(128)
	whale.animate(20.0, Vector3(35,-70,-360))
	check(whale.phase_offset == phase and visual_pose(whale) == first_pose, "A repeated seed and time reproduce the encounter exactly")
	var meshes: Array[Node] = whale.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "The encounter contains visible whale geometry")
	var combined := AABB()
	var has_bounds := false
	for visual: MeshInstance3D in meshes:
		for corner: Vector3 in corners(visual.mesh.get_aabb()):
			var point: Vector3 = whale.to_local(visual.to_global(corner))
			if not has_bounds:
				combined = AABB(point,Vector3.ZERO)
				has_bounds = true
			else:
				combined = combined.expand(point)
	check(combined.size.z >= 16.0 and combined.size.x >= 7.0, "The whale has an unmistakably giant body and broad pectoral span")
	var deep_route := true
	var bounded_route := true
	var bottom_clear := true
	var min_clearance := INF
	var min_depth := INF
	var max_depth := 0.0
	for step in range(361):
		whale.animate(float(step)*3.0, Vector3(35,-70,-360))
		var center: Vector3 = whale.global_position
		min_depth = minf(min_depth,-center.y)
		max_depth = maxf(max_depth,-center.y)
		deep_route = deep_route and center.y <= -50.0 and center.y >= -95.0
		bounded_route = bounded_route and absf(center.x-35.0) <= 110.0 and absf(center.z+360.0) <= 110.0
		# Sample complete bounds plus the shader's tail sway and fin movement,
		# not merely the pivot or undeformed mesh footprint.
		for visual: MeshInstance3D in meshes:
			for corner: Vector3 in corners(visual.mesh.get_aabb()):
				for sway: float in [-1.5, 0.0, 1.5]:
					var world: Vector3 = visual.to_global(corner+Vector3(sway,-0.3,0))
					var clearance: float = world.y-Ocean.seabed_height(world.x,world.z)
					min_clearance = minf(min_clearance,clearance)
					bottom_clear = bottom_clear and clearance >= 5.5
	check(deep_route and bounded_route, "The full patrol stays in the northern deep-water basin")
	check(bottom_clear, "The whole giant silhouette clears actual terrain (minimum %.2fm)" % min_clearance)
	print("Whale patrol depth: %.2f–%.2fm; minimum animated clearance: %.2fm" % [min_depth,max_depth,min_clearance])
	whale.animate(30.0, Vector3(35,-70,-360))
	var frozen: Array = visual_pose(whale)
	whale.animate(30.0, Vector3(35,-70,-360))
	check(visual_pose(whale) == frozen, "A frozen simulation clock freezes patrol and articulated animation")
	whale.animate(30.5, Vector3(35,-70,-360))
	check(visual_pose(whale) != frozen, "Advancing the simulation produces slow swimming motion")
	whale.animate(30.5, Vector3(450,-5,450))
	check(not whale.visible, "The distant giant is culled away from its habitat")
	whale.animate(30.5, whale.global_position+Vector3(0,0,20))
	check(whale.visible, "A nearby diver can see the deep-water encounter")
	check(whale.find_children("*", "CollisionObject3D", true, false).is_empty(), "The peaceful encounter adds no collision hazard or attack body")
	check(game.fish.size() == existing_fish and game.fish_population_count() == existing_fish and game.hazards.size() == existing_hazards, "The whale does not replace ordinary catches or add hazards")
	check(memory._save_data() == before and memory.saves == 0, "Patrol setup and animation never write player progress")
	phase = whale.phase_offset
	DiveFixture.visit(game,1,true)
	check(game.whale_shark.get_instance_id() == instance_id and whale.phase_offset == phase, "GM relocation keeps the same single encounter for the current dive")
	game.toggle_pause()
	frozen = visual_pose(whale)
	game.set_physics_process(true)
	for frame in range(8):
		await physics_frame
	game.set_physics_process(false)
	check(game.state == "paused" and visual_pose(whale) == frozen, "The real pause state freezes the giant across physics frames")
	game.toggle_pause()
	game.finish_dive(false)
	game.wildlife_rng.seed = 1971
	game.start_dive(false,false)
	check(game.whale_shark.get_instance_id() == instance_id and whale.spawned and whale.phase_offset != phase, "A new dive refreshes the patrol without creating another whale")
	var encounter_count := 0
	for child: Node in game.ocean_root.get_children():
		if child.get_script() == Shark:
			encounter_count += 1
	check(encounter_count == 1, "Only one whale shark exists after repeated dive setup")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver deep whale shark (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
