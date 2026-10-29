extends SceneTree
## Rare wildlife uses the real game lifecycle without durable save access.
const Ocean = preload("res://scripts/ocean_config.gd")
const Shark = preload("res://scripts/thresher_shark.gd")
var checks: int = 0
var failures: int = 0

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
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
	var shark: Node3D = game.canyon_shark
	_check(shark != null and shark.get_meta("ambient_only", false), "The actual ocean includes a separate ambient thresher encounter")
	if shark == null:
		game.free()
		quit(1)
		return
	var before: Dictionary = memory._save_data().duplicate(true)
	var spawned_count: int = 0
	var first_spawn: int = -1
	var first_absent: int = -1
	for seed_value in range(1000):
		var present: bool = shark.begin_dive(seed_value)
		spawned_count += int(present)
		if present and first_spawn < 0:
			first_spawn = seed_value
		if not present and first_absent < 0:
			first_absent = seed_value
	_check(spawned_count > 280 and spawned_count < 420 and first_spawn >= 0 and first_absent >= 0, "Per-dive rolls produce both outcomes at roughly the configured 35 percent rate")
	shark.begin_dive(first_spawn)
	var roll: float = shark.spawn_roll
	var phase: float = shark.phase_offset
	shark.begin_dive(first_spawn)
	_check(shark.spawned and shark.spawn_roll == roll and shark.phase_offset == phase, "A repeated seed reproduces the encounter and its patrol phase")
	shark.begin_dive(first_absent)
	shark.animate(10.0, Ocean.CANYON_CENTER)
	_check(not shark.spawned and not shark.visible, "A failed roll stays hidden when its animation is updated")
	shark.begin_dive(first_absent, true)
	_check(shark.spawned, "A forced test encounter is available independently of the random roll")
	var route_clear: bool = true
	var route_local: bool = true
	for step in range(180):
		shark.animate(float(step), Vector3(-210,-80,-230))
		var point: Vector3 = shark.global_position
		route_clear = route_clear and point.y > Ocean.seabed_height(point.x, point.z) + 20.0
		route_local = route_local and absf(point.z - Ocean.CANYON_CENTER.z) < 93.0 and absf(point.x - Ocean.canyon_center_x(point.z)) < 8.1
	_check(route_clear and route_local, "The full patrol stays above the actual canyon floor and within its local channel")
	shark.animate(30.0, Vector3(-210,-80,-230))
	var position_before: Vector3 = shark.position
	var tail_before: Transform3D = shark.get_node("Tail").transform
	shark.animate(30.0, Vector3(-210,-80,-230))
	_check(shark.position == position_before and shark.get_node("Tail").transform == tail_before, "An unchanged simulation clock freezes both patrol and tail motion")
	shark.animate(30.4, Vector3(-210,-80,-230))
	_check(shark.position.distance_to(position_before) > 0.1 and shark.get_node("Tail").transform != tail_before, "Advancing the dive clock moves the animal and articulates its long tail")
	shark.animate(30.4, Vector3(450,-5,450))
	_check(not shark.visible, "The shark is distance culled away from the canyon")
	var body: MeshInstance3D = shark.get_node("BodyAndFins")
	var tail: MeshInstance3D = shark.get_node("Tail/LongUpperLobe")
	_check(tail.mesh.get_aabb().size.z > 3.0 and tail.mesh.get_aabb().size.y > 3.0 and body.mesh.get_aabb().size.z > 3.0, "The original model has a substantial trunk and its defining long upper tail lobe")
	var no_collision: bool = true
	for child in shark.find_children("*", "CollisionObject3D", true, false):
		no_collision = false
	_check(no_collision, "The ambient encounter adds no hazards or blocking collision")
	var clone: Node3D = Shark.build(game.ocean_root)
	_check(clone.get_node("BodyAndFins").mesh == body.mesh and clone.get_node("Tail/LongUpperLobe").mesh == tail.mesh, "Repeated encounters reuse shared meshes and materials")
	clone.free()
	shark.begin_dive(455, true)
	shark.animate(12, Vector3(-210,-80,-230))
	roll = shark.spawn_roll
	phase = shark.phase_offset
	game.open_gm_menu()
	game.gm_select_dive_site(1, true)
	_check(shark.spawned and shark.spawn_roll == roll and shark.phase_offset == phase, "GM relocation preserves the current dive's encounter roll")
	game.toggle_pause()
	position_before = shark.position
	tail_before = shark.get_node("Tail").transform
	game.set_physics_process(true)
	for frame in range(8):
		await physics_frame
	game.set_physics_process(false)
	_check(game.state == "paused" and shark.position == position_before and shark.get_node("Tail").transform == tail_before, "The real pause state freezes the encounter in physics frames")
	_check(game.fish.size() == 151 and game.fish_population_count() == 151 and game.pickups.size() > 0, "Rare wildlife leaves the ordinary fish population and existing pickups intact")
	_check(memory._save_data() == before and memory.saves == 0, "Encounter rolls, animation and GM testing never write durable progress")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver canyon wildlife (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
