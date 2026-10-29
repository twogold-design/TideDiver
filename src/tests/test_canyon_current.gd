extends SceneTree
## Canyon terrain and current, measured through real physics frames and memory progress.
const Ocean = preload("res://scripts/ocean_config.gd")
const ACTIONS = ["swim_left", "swim_right", "swim_forward", "swim_back", "ascend", "descend", "boost", "stealth"]

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var checks: int = 0
var failures: int = 0
var game: Node
var memory: MemoryProgression

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		printerr("FAIL: main scene could not load")
		quit(1)
		return
	game = packed.instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	await process_frame
	game.start_dive(false, false)
	await physics_frame
	await process_frame
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	_test_terrain()
	_test_winding_routes()
	_test_submerged_ecology()
	_test_current_field()
	await _test_swimming()
	await _test_pause_and_entry()
	var garden: Node = game.ocean_root.get_node_or_null("OuterOcean/amber_reef/CoralGarden")
	_check(game.fish.size() == 151 and game.fish_population_count() == 151 and Ocean.DIVE_SITES.size() == 6, "Canyon updates retain all six departure sites and the sparse ordinary fish population")
	_check(game.storm_school != null and int(game.storm_school.get_meta("fish_count", 0)) == 420 and garden != null and int(garden.get_meta("patch_count", 0)) == 150, "The actual ocean still contains the fish storm and the full coral garden")
	_check(memory._save_data() == progress_before and memory.saves == 0, "Current, movement, pause and entry tests do not mutate or save player progress")
	_release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver canyon current (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_terrain() -> void:
	var terrain_matches: bool = true
	var deep_floor: bool = true
	var exposed_banks: bool = true
	for z: float in [-380.0, -330.0, -280.0, -230.0, -180.0, -130.0, -80.0]:
		var x: float = Ocean.canyon_center_x(z)
		var floor_hit: Dictionary = _terrain_hit(x, z)
		var west_hit: Dictionary = _terrain_hit(x - 43, z)
		var east_hit: Dictionary = _terrain_hit(x + 43, z)
		var complete: bool = not floor_hit.is_empty() and not west_hit.is_empty() and not east_hit.is_empty()
		_check(complete, "Real terrain rays reach the canyon floor and both banks at z %.0f" % z)
		if not complete:
			terrain_matches = false
			deep_floor = false
			continue
		var floor_y: float = floor_hit.position.y
		_check(west_hit.position.y - floor_y >= 38 and east_hit.position.y - floor_y >= 38, "The enlarged canyon floor is at least thirty-eight metres below both banks at z %.0f" % z)
		deep_floor = deep_floor and floor_y < -108
		exposed_banks = exposed_banks and west_hit.position.y > 10.0 and east_hit.position.y > 10.0
		for side: float in [-1.0, 1.0]:
			var collision := KinematicCollision3D.new()
			var start := Vector3(x,5,z)
			var blocked: bool = game.player.test_move(Transform3D(Basis.IDENTITY,start),Vector3(side*60,0,0),collision)
			_check(blocked and collision.get_collider() != null and collision.get_collider().name == "TerrainCollision", "The actual emergent %s mountain blocks a diver above sea level at z %.0f" % ["west" if side < 0 else "east",z])
		for hit in [floor_hit, west_hit, east_hit]:
			terrain_matches = terrain_matches and absf(hit.position.y - Ocean.seabed_height(hit.position.x, hit.position.z)) < 0.03
	_check(terrain_matches and deep_floor, "Deep canyon collision surfaces agree with the rendered terrain height contract")
	var refined_matches := true
	for z: float in [-400.7,-300.01,-299.99,-230.3,-100.01,-99.99,-50.7]:
		for offset: float in [0.3,18.7,26.1,31.3,43.3]:
			var x: float = Ocean.canyon_center_x(z)+offset
			var hit: Dictionary = _terrain_hit(x,z)
			refined_matches = refined_matches and not hit.is_empty() and absf(hit.position.y-Ocean.seabed_height(x,z)) < .03
	_check(refined_matches,"Fine canyon collision matches fractional floor, wall and chunk seam samples")
	var seams_match := true
	for z: float in [-499.0,-355.0,-301.0,-231.0,-101.0,-1.0,99.0]:
		for x: float in [-300.0,-100.0]:
			seams_match = seams_match and absf(Ocean.seabed_height(x-.001,z)-Ocean.seabed_height(x+.001,z)) < .04
	_check(seams_match,"Two-metre canyon terrain stitches continuously into the four-metre shelf")
	_check(exposed_banks, "Both mountain ridges rise above the sea along the winding canyon's full core")
	var corridor_named: bool = true
	for z: float in [Ocean.CANYON_CENTER.z-Ocean.CANYON_HALF_LENGTH+2.0, Ocean.CANYON_CENTER.z+Ocean.CANYON_HALF_LENGTH-2.0]:
		corridor_named = corridor_named and Ocean.zone_for_position(Vector3(Ocean.canyon_center_x(z), -70, z)).get("id", "") == "twin_gates"
	_check(corridor_named and Ocean.CANYON_HALF_LENGTH*2.0 >= 450 and Ocean.ZONES[0].radius == 70.0, "Both ends of the 450-metre gorge retain the canyon navigation label and side-area radius")
	var mouths_submerged: bool = true
	for side: float in [-1.0,1.0]:
		var z: float = Ocean.CANYON_CENTER.z+side*Ocean.CANYON_HALF_LENGTH
		for offset: float in [-43.0,0.0,43.0]:
			var hit: Dictionary = _terrain_hit(Ocean.canyon_center_x(z)+offset,z)
			mouths_submerged = mouths_submerged and not hit.is_empty() and hit.position.y < -40.0
	_check(mouths_submerged,"Both exposed mountain chains taper into navigable underwater canyon mouths")

func _test_winding_routes() -> void:
	var minimum_x := INF
	var maximum_x := -INF
	for lane: float in [-8.0,0.0,8.0]:
		var clear := true
		var previous := Vector3.ZERO
		for step in range(149):
			var z: float = lerpf(Ocean.CANYON_CENTER.z-Ocean.CANYON_HALF_LENGTH+3.0,Ocean.CANYON_CENTER.z+Ocean.CANYON_HALF_LENGTH-3.0,float(step)/148.0)
			var point := Vector3(Ocean.canyon_center_x(z)+lane,-50,z)
			minimum_x = minf(minimum_x,point.x-lane)
			maximum_x = maxf(maximum_x,point.x-lane)
			var collision := KinematicCollision3D.new()
			if step>0 and game.player.test_move(Transform3D(Basis.IDENTITY,previous),point-previous,collision):
				clear = false
				printerr("Winding channel obstruction at %s: %s" % [point,collision.get_collider()])
				break
			clear = clear and point.y < -1.0 and point.y>Ocean.seabed_height(point.x,point.z)+1.0
			previous = point
		_check(clear,"A real diver can traverse the whole submerged winding channel at lateral offset %.0f" % lane)
	_check(maximum_x-minimum_x>48.0,"The navigable canyon visibly bends across more than forty-eight metres instead of remaining straight")

func _test_submerged_ecology() -> void:
	var life: Node3D = game.ocean_root.get_node_or_null("MarineLife")
	var submerged: bool = life != null and life.organisms.size() == 67
	var highest := -INF
	if life != null:
		for time: float in [0.0,12.0,47.0,210.0]:
			life.animate(time,Ocean.CANYON_CENTER)
			for animal: Dictionary in life.organisms:
				var visual: MultiMeshInstance3D = animal.visual
				var pose: Transform3D = visual.global_transform*visual.multimesh.get_instance_transform(animal.index)
				var vertices: PackedVector3Array = visual.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					highest = maxf(highest,(pose*vertex).y)
					submerged = submerged and (pose*vertex).y < -1.0
		life.reset()
	_check(submerged,"All sixty-seven animated marine animals remain entirely underwater after emergent mountains are added (highest %.2f)" % highest)

func _terrain_hit(x: float, z: float) -> Dictionary:
	var excluded: Array[RID] = [game.player.get_rid()]
	for attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -130, z), 1, excluded)
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider.name == "TerrainCollision":
			return hit
		# Inspect the real terrain beneath authored gate and rock geometry.
		excluded.append(hit.collider.get_rid())
	return {}

func _test_current_field() -> void:
	var z: float = Ocean.CANYON_CENTER.z
	var x: float = Ocean.canyon_center_x(z)
	var full: Vector3 = Ocean.current_velocity(Vector3(x, -50, z))
	_check(full.dot(Ocean.canyon_tangent(z)) > 2.19 and full.y == 0 and absf(full.length() - 2.2) < 0.001, "The faster deep canyon current reaches 2.2 m/s downstream without a vertical force")
	var follows_bends := true
	var changes_direction := false
	var previous_direction := Vector3.ZERO
	for sample_z: float in [-400.0,-350.0,-290.0,-230.0,-170.0,-110.0,-60.0]:
		var point := Vector3(Ocean.canyon_center_x(sample_z),-50,sample_z)
		var current: Vector3 = Ocean.current_velocity(point)
		var surveyed_direction := Vector3(Ocean.canyon_center_x(sample_z+1.0)-Ocean.canyon_center_x(sample_z-1.0),0,2.0).normalized()
		follows_bends = follows_bends and absf(current.length()-2.2)<.001 and current.normalized().dot(surveyed_direction)>.999 and current.normalized().dot(Ocean.canyon_tangent(sample_z))>.999
		changes_direction = changes_direction or (not previous_direction.is_zero_approx() and previous_direction.x*current.x<0.0)
		previous_direction = current
	_check(follows_bends and changes_direction,"The current follows the measured local channel direction through successive opposing bends")
	var middle: Vector3 = Ocean.current_velocity(Vector3(x, -35, z))
	_check(middle.length() > 0 and middle.length() < full.length(), "Current strength increases gradually between twenty-five and forty-five metres deep")
	var quiet: bool = true
	for point in [Vector3(x, -2, z), Vector3(x, -24, z), Vector3(x + 80, -50, z), Vector3(x, -50, z + Ocean.CANYON_HALF_LENGTH+1.0), Vector3(x+43,5,z),Vector3(400, -50, 400)]:
		quiet = quiet and Ocean.current_velocity(point).is_zero_approx()
	_check(quiet, "Surface water, the shallow layer and locations outside the canyon remain still")
	var previous: float = full.length()
	var smooth_edge: bool = true
	var has_transition: bool = false
	for offset in range(1, 63):
		var magnitude: float = Ocean.current_velocity(Vector3(x + offset, -50, z)).length()
		smooth_edge = smooth_edge and magnitude <= previous + 0.001 and previous - magnitude < 0.35
		has_transition = has_transition or (magnitude > 0.01 and magnitude < full.length() - 0.01)
		previous = magnitude
	_check(smooth_edge and has_transition and previous < 0.001, "The lateral current boundary fades smoothly to still water")
	for side: float in [-1.0,1.0]:
		previous = full.length()
		var smooth_mouth := true
		for distance in range(180,227):
			var sample_z: float = z+side*float(distance)
			var magnitude: float = Ocean.current_velocity(Vector3(Ocean.canyon_center_x(sample_z),-50,sample_z)).length()
			smooth_mouth = smooth_mouth and magnitude<=previous+.001 and previous-magnitude<.09
			previous = magnitude
		_check(smooth_mouth and previous<.001,"Current fades continuously into still water at the %s mouth" % ["south" if side<0 else "north"])

func _test_swimming() -> void:
	var flowing := Vector3(Ocean.canyon_center_x(-250.0), -50, -250)
	var calm := Vector3(400, -50, 400)
	var tangent: Vector3 = Ocean.canyon_tangent(flowing.z)
	var heading: float = atan2(tangent.x,tangent.z)
	var right: Vector3 = Vector3.RIGHT.rotated(Vector3.UP,heading)
	var calm_idle: Dictionary = await _measure_motion(calm, "", heading)
	var calm_forward: Dictionary = await _measure_motion(calm, "swim_back", heading)
	var calm_side: Dictionary = await _measure_motion(calm, "swim_right", heading)
	var calm_up: Dictionary = await _measure_motion(calm, "ascend", heading)
	var drift: Dictionary = await _measure_motion(flowing, "", heading)
	var downstream: Dictionary = await _measure_motion(flowing, "swim_back", heading)
	var upstream: Dictionary = await _measure_motion(flowing, "swim_forward", heading)
	var sideways: Dictionary = await _measure_motion(flowing, "swim_right", heading)
	var upward: Dictionary = await _measure_motion(flowing, "ascend", heading)
	_check(calm_idle.displacement.length() < 0.01 and drift.displacement.dot(tangent) > 0.95 and drift.displacement.dot(tangent) < 1.20, "The stronger current carries an idle diver about a metre downstream in half a second")
	var forward_ratio: float = downstream.displacement.dot(tangent) / calm_forward.displacement.dot(tangent)
	var reverse_ratio: float = -upstream.displacement.dot(tangent) / calm_forward.displacement.dot(tangent)
	_check(forward_ratio > 1.28 and forward_ratio < 1.42, "Actual downstream swimming is substantially faster than still water (ratio %.3f)" % forward_ratio)
	_check(reverse_ratio > 0.58 and reverse_ratio < 0.72 and upstream.displacement.dot(tangent) < -1.8, "Upstream swimming remains controllable against the stronger current (ratio %.3f)" % reverse_ratio)
	_check(sideways.displacement.dot(right) > calm_side.displacement.dot(right) * 0.9 and sideways.displacement.dot(right) < calm_side.displacement.dot(right) * 1.1 and sideways.displacement.dot(tangent) > 0.2, "Lateral steering remains effective while the current carries the diver downstream")
	_check(absf(upward.displacement.y - calm_up.displacement.y) < 0.03 and upward.displacement.y > 3 and upward.displacement.dot(tangent) > 0.2, "The diver can ascend at normal speed while drifting")
	var clear: bool = true
	for sample in [calm_idle, calm_forward, calm_side, calm_up, drift, downstream, upstream, sideways, upward]:
		clear = clear and sample.collisions == 0 and absf(sample.elapsed - 0.5) < 0.002
	_check(clear, "Movement comparisons use matching real physics time in water clear of gate walls and terrain")
	var equal_air: bool = true
	for sample in [drift, downstream, upstream, sideways]:
		equal_air = equal_air and absf(sample.air_used - calm_forward.air_used) < 0.002
	_check(equal_air and absf(drift.air_used - 0.495) < 0.003, "The current adds no air cost beyond normal breathing at the same depth")
	_check(drift.current.dot(tangent) > 2.19 and absf(drift.current.y) < 0.001 and calm_idle.current.is_zero_approx(), "The game's live drift value follows the faster local current field")

func _measure_motion(start: Vector3, action: String, heading: float) -> Dictionary:
	await process_frame
	_release_actions()
	game.state = "dive"
	game.entry_active = false
	game.player.position = start
	game.player.velocity = Vector3.ZERO
	game.player.rotation = Vector3(0,heading,0)
	game.yaw = heading
	game.pitch = -0.12
	game.oxygen = 100
	game.depth_record = 0
	game.hurt_cooldown = 0
	game.poison_timer = 0
	if not action.is_empty():
		Input.action_press(action)
	game.set_physics_process(true)
	await physics_frame
	var position_before: Vector3 = game.player.position
	var air_before: float = game.oxygen
	var clock_before: float = game.clock
	var collisions: int = 0
	for frame in range(30):
		await physics_frame
		collisions += game.player.get_slide_collision_count()
	game.set_physics_process(false)
	_release_actions()
	return {"displacement":game.player.position - position_before, "air_used":air_before - game.oxygen, "elapsed":game.clock - clock_before, "collisions":collisions, "current":game.drift_current}

func _test_pause_and_entry() -> void:
	game.toggle_pause()
	var position_before: Vector3 = game.player.position
	var air_before: float = game.oxygen
	var clock_before: float = game.clock
	game.set_physics_process(true)
	for frame in range(10):
		await physics_frame
	game.set_physics_process(false)
	_check(game.state == "paused" and game.player.position == position_before and game.oxygen == air_before and game.clock == clock_before, "Pause freezes current-driven motion and breathing in real physics frames")
	game.toggle_pause()
	game.state = "dock"
	game.start_dive(true, false, 1)
	var entry_origin: Vector3 = game.dive_origin
	air_before = game.oxygen
	game.set_physics_process(true)
	for frame in range(15):
		await physics_frame
	game.set_physics_process(false)
	_check(game.entry_active and absf(game.player.position.x - entry_origin.x) < 0.001 and absf(game.player.position.z - entry_origin.z - 17.5) < 0.001 and game.drift_current.is_zero_approx() and game.oxygen == air_before, "The initial boat-entry animation follows its authored path without current drift or air use")
	var entry_clear := true
	var frames := 0
	game.set_physics_process(true)
	while game.entry_active and frames<210:
		await physics_frame
		frames += 1
		var point: Vector3 = game.player.position
		entry_clear = entry_clear and point.y>Ocean.seabed_height(point.x,point.z)+1.0 and game.drift_current.is_zero_approx() and game.oxygen == air_before
	game.set_physics_process(false)
	var landed: Vector3 = entry_origin+Vector3(0,-6,25)
	_check(not game.entry_active and entry_clear and game.player.position.distance_to(landed)<.03,"The full canyon boat jump and immersion finish in open water clear of the emergent mountains without air cost")

func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
