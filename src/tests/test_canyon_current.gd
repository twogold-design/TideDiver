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
	await physics_frame
	await process_frame
	game.start_dive(false, false)
	await physics_frame
	await process_frame
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	_test_terrain()
	_test_current_field()
	await _test_swimming()
	await _test_pause_and_entry()
	var garden: Node = game.ocean_root.get_node_or_null("OuterOcean/amber_reef/CoralGarden")
	_check(game.fish.size() == 167 and game.fish_population_count() == 167 and Ocean.DIVE_SITES.size() == 7, "Canyon updates retain all seven departure sites and the sparse ordinary fish population")
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
	for z: float in [-260.0, -230.0, -200.0]:
		var x: float = Ocean.canyon_center_x(z)
		var floor_hit: Dictionary = _terrain_hit(x, z)
		var west_hit: Dictionary = _terrain_hit(x - 40, z)
		var east_hit: Dictionary = _terrain_hit(x + 40, z)
		var complete: bool = not floor_hit.is_empty() and not west_hit.is_empty() and not east_hit.is_empty()
		_check(complete, "Real terrain rays reach the canyon floor and both banks at z %.0f" % z)
		if not complete:
			terrain_matches = false
			deep_floor = false
			continue
		var floor_y: float = floor_hit.position.y
		_check(west_hit.position.y - floor_y >= 25 and east_hit.position.y - floor_y >= 25, "Actual canyon floor is at least twenty-five metres below both banks at z %.0f" % z)
		deep_floor = deep_floor and floor_y < -90
		for hit in [floor_hit, west_hit, east_hit]:
			terrain_matches = terrain_matches and absf(hit.position.y - Ocean.seabed_height(hit.position.x, hit.position.z)) < 0.03
	_check(terrain_matches and deep_floor, "Deep canyon collision surfaces agree with the rendered terrain height contract")

func _terrain_hit(x: float, z: float) -> Dictionary:
	var excluded: Array[RID] = [game.player.get_rid()]
	for attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, -2, z), Vector3(x, -130, z), 1, excluded)
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
	_check(full.z > 0.75 and full.y == 0 and full.length() <= Ocean.CANYON_CURRENT_SPEED + 0.001, "The deep canyon current flows downstream without a vertical force or excessive speed")
	var middle: Vector3 = Ocean.current_velocity(Vector3(x, -35, z))
	_check(middle.length() > 0 and middle.length() < full.length(), "Current strength increases gradually between twenty-five and forty-five metres deep")
	var quiet: bool = true
	for point in [Vector3(x, -2, z), Vector3(x, -24, z), Vector3(x + 80, -50, z), Vector3(x, -50, z + 200), Vector3(400, -50, 400)]:
		quiet = quiet and Ocean.current_velocity(point).is_zero_approx()
	_check(quiet, "Surface water, the shallow layer and locations outside the canyon remain still")
	var previous: float = full.length()
	var smooth_edge: bool = true
	var has_transition: bool = false
	for offset in range(2, 62, 2):
		var magnitude: float = Ocean.current_velocity(Vector3(x + offset, -50, z)).length()
		smooth_edge = smooth_edge and magnitude <= previous + 0.001 and previous - magnitude < 0.35
		has_transition = has_transition or (magnitude > 0.01 and magnitude < full.length() - 0.01)
		previous = magnitude
	_check(smooth_edge and has_transition and previous < 0.001, "The lateral current boundary fades smoothly to still water")

func _test_swimming() -> void:
	var flowing := Vector3(Ocean.canyon_center_x(-250.0), -50, -250)
	var calm := Vector3(400, -50, 400)
	var calm_idle: Dictionary = await _measure_motion(calm, "")
	var calm_forward: Dictionary = await _measure_motion(calm, "swim_back")
	var calm_side: Dictionary = await _measure_motion(calm, "swim_right")
	var calm_up: Dictionary = await _measure_motion(calm, "ascend")
	var drift: Dictionary = await _measure_motion(flowing, "")
	var downstream: Dictionary = await _measure_motion(flowing, "swim_back")
	var upstream: Dictionary = await _measure_motion(flowing, "swim_forward")
	var sideways: Dictionary = await _measure_motion(flowing, "swim_right")
	var upward: Dictionary = await _measure_motion(flowing, "ascend")
	_check(calm_idle.displacement.length() < 0.01 and drift.displacement.z > 0.25 and drift.displacement.z < 0.55, "An idle diver is carried downstream only inside the flowing canyon")
	var forward_ratio: float = downstream.displacement.z / calm_forward.displacement.z
	var reverse_ratio: float = -upstream.displacement.z / calm_forward.displacement.z
	_check(forward_ratio > 1.08 and forward_ratio < 1.22, "Actual downstream swimming is faster than still water (ratio %.3f)" % forward_ratio)
	_check(reverse_ratio > 0.80 and reverse_ratio < 0.95 and upstream.displacement.z < -2, "Upstream swimming remains controllable with mild resistance (ratio %.3f)" % reverse_ratio)
	_check(sideways.displacement.x > calm_side.displacement.x * 0.9 and sideways.displacement.x < calm_side.displacement.x * 1.1 and sideways.displacement.z > 0.2, "Lateral steering remains effective while the current carries the diver downstream")
	_check(absf(upward.displacement.y - calm_up.displacement.y) < 0.03 and upward.displacement.y > 3 and upward.displacement.z > 0.2, "The diver can ascend at normal speed while drifting")
	var clear: bool = true
	for sample in [calm_idle, calm_forward, calm_side, calm_up, drift, downstream, upstream, sideways, upward]:
		clear = clear and sample.collisions == 0 and absf(sample.elapsed - 0.5) < 0.002
	_check(clear, "Movement comparisons use matching real physics time in water clear of gate walls and terrain")
	var equal_air: bool = true
	for sample in [drift, downstream, upstream, sideways]:
		equal_air = equal_air and absf(sample.air_used - calm_forward.air_used) < 0.002
	_check(equal_air and absf(drift.air_used - 0.495) < 0.003, "The current adds no air cost beyond normal breathing at the same depth")
	_check(drift.current.z > 0.75 and absf(drift.current.y) < 0.001 and calm_idle.current.is_zero_approx(), "The game's live drift value follows the local current field")

func _measure_motion(start: Vector3, action: String) -> Dictionary:
	await process_frame
	_release_actions()
	game.state = "dive"
	game.entry_active = false
	game.player.position = start
	game.player.velocity = Vector3.ZERO
	game.player.rotation = Vector3.ZERO
	game.yaw = 0
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
	game.start_dive(true, false)
	var entry_origin: Vector3 = game.dive_origin
	air_before = game.oxygen
	game.set_physics_process(true)
	for frame in range(15):
		await physics_frame
	game.set_physics_process(false)
	_check(game.entry_active and absf(game.player.position.x - entry_origin.x) < 0.001 and absf(game.player.position.z - entry_origin.z - 17.5) < 0.001 and game.drift_current.is_zero_approx() and game.oxygen == air_before, "The initial boat-entry animation follows its authored path without current drift or air use")

func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
