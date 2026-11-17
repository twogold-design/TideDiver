extends SceneTree
## Real wreck patrol trajectories, scenery clearance and predator state transitions.
const Brain = preload("res://scripts/fish_brain.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const DiveFixture = preload("res://tests/dive_fixture.gd")
const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var game: Node

class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func residents() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in game.fish:
		if item.get("wreck_barracuda",false):
			result.append(item)
	return result

func body_clear(item: Dictionary) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = .55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	for z: float in [-1.55, 0.0, 1.55]:
		var point: Vector3 = item.node.to_global(Vector3(0,0,z))
		if point.y-Ocean.seabed_height(point.x,point.z) < .55:
			return false
		query.transform = Transform3D(Basis.IDENTITY,point)
		if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			return false
	return true

func watch_from_above() -> void:
	game.player.position = game.explorable_wreck.to_global(Vector3(0,45,0))
	game.player.position.y = minf(-5.0,game.player.position.y)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	game.start_dive(false,false,2)
	await physics_frame
	var fish: Array[Dictionary] = residents()
	check(fish.size() == 6, "Exactly six extra catchable barracudas occupy the wreck")
	check(game.fish.size() == 213 and game.fish_population_count() == 213, "The authored addition raises the full catchable population by six")
	if fish.size() != 6:
		game.free()
		quit(1)
		return
	var separated := true
	var configured := true
	var spawn_clear := true
	for index in range(fish.size()):
		var item: Dictionary = fish[index]
		configured = configured and item.kind == 13 and item.get("habitat_site","") == "merchant_wreck" and item.get("barracuda_lane",[]).size() == 2
		spawn_clear = spawn_clear and body_clear(item)
		for other in range(index):
			separated = separated and item.node.position.distance_to(fish[other].node.position) >= 6.0
	check(configured, "Wreck residents use individual two-ended patrol lanes and the canonical barracuda species")
	check(separated and spawn_clear, "Added barracudas begin separated and clear of actual wreck collision")
	watch_from_above()
	for item: Dictionary in fish:
		test_route(item)
	await test_attack_and_recovery(fish[0])
	test_generic_barracuda()
	await test_lifecycle(fish)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver wreck barracuda patrol (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func test_route(item: Dictionary) -> void:
	var lane: Array = item.get("barracuda_lane",item.get("barracuda_route",[]))
	var start: Vector3 = lane[0]
	var axis: Vector3 = (lane[1]-start).normalized()
	var length: float = start.distance_to(lane[1])
	var min_along := INF
	var max_along := -INF
	var max_side := 0.0
	var straight := 0
	var straight_samples := 0
	var visits := 0
	var last_end := -1
	var clear := true
	var smooth := true
	for frame in range(3600):
		var before: Vector3 = item.direction
		game.clock += DT
		Brain.advance(game,item,DT)
		var point: Vector3 = item.node.position
		var along: float = (point-start).dot(axis)
		var side: float = ((point-start)-axis*along).length()
		min_along = minf(min_along,along)
		max_along = maxf(max_along,along)
		max_side = maxf(max_side,side)
		if along > length*.18 and along < length*.82:
			straight_samples += 1
			straight += int(absf((item.direction as Vector3).dot(axis)) > .88)
		var end := 0 if along < length*.15 else (1 if along > length*.85 else -1)
		if end >= 0 and end != last_end:
			visits += 1
			last_end = end
		if frame % 30 == 0:
			clear = clear and body_clear(item)
		if frame > 10:
			smooth = smooth and before.angle_to(item.direction) < .13
	check(max_along-min_along >= length*.8 and visits >= 4, "The barracuda traverses its long route and repeatedly returns instead of circling in place")
	check(straight_samples > 200 and float(straight)/maxi(1,straight_samples) > .65 and max_side < 15.0, "Patrol consists mainly of straight swimming with bounded end turns")
	check(clear and smooth, "Actual patrol clears ship and terrain while changing heading smoothly")
	print("Barracuda route: %.1fm span, %d end visits, %.1fm lateral offset, %.1f%% straight" % [max_along-min_along,visits,max_side,100.0*float(straight)/maxi(1,straight_samples)])

func test_attack_and_recovery(item: Dictionary) -> void:
	item.state = "patrol"
	item.attack_cooldown = 0.0
	item.alerted = false
	game.player.position = item.node.position+(item.direction as Vector3)*7.0
	game.oxygen = 100.0
	game.hurt_cooldown = 0.0
	Brain.advance(game,item,.01)
	check(item.state == "windup" and game.oxygen == 100.0, "A nearby diver still triggers visible windup before damage")
	for frame in range(36):
		Brain.advance(game,item,DT)
	var committed: Vector3 = item.direction
	check(item.state == "charge", "Windup transitions into the canonical straight lunge")
	game.player.position = item.node.position+Vector3.UP*12.0
	for frame in range(6):
		Brain.advance(game,item,DT)
	check(item.state == "charge" and (item.direction as Vector3).dot(committed) > .999, "The lunge commits to one direction instead of homing in a circle")
	game.player.position = item.node.position+Vector3.UP*.1
	Brain.advance(game,item,.01)
	check(item.state == "recover" and is_equal_approx(game.oxygen,88.0), "Contact applies the same single twelve-point hit and recovery")
	watch_from_above()
	var recovery_origin: Vector3 = item.node.position
	for frame in range(1500):
		game.clock += DT
		Brain.advance(game,item,DT)
	var lane: Array = item.barracuda_lane
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(item.node.position,lane[0],lane[1])
	check(item.state == "patrol" and item.node.position.distance_to(closest) < 15.0 and recovery_origin.distance_to(item.node.position) > 8.0, "After attacking, barracuda rejoins its local lane and continues travelling")
	check(body_clear(item), "Recovery leaves the whole barracuda outside the wreck")
	await process_frame

func test_generic_barracuda() -> void:
	var item: Dictionary = game._add_fish(13,Vector3(150,-15,180))
	game.player.position = item.home+Vector3(45,5,0)
	Brain.advance(game,item,DT)
	var route: Array = item.get("barracuda_route",[])
	check(not item.has("barracuda_lane") and route.size() == 2 and route[0].distance_to(route[1]) >= 44.0, "Ordinary open-water barracudas also choose long clear routes without an authored wreck lane")
	if route.size() == 2:
		test_route(item)
	game.fish.erase(item)
	item.node.free()
	watch_from_above()

func test_lifecycle(fish: Array[Dictionary]) -> void:
	var ids: Array[int] = []
	for item: Dictionary in fish:
		ids.append(item.node.get_instance_id())
	DiveFixture.visit(game,1,true)
	var moved: Array[Dictionary] = residents()
	var preserved := moved.size() == 6
	for item: Dictionary in moved:
		preserved = preserved and ids.has(item.node.get_instance_id())
	check(preserved, "GM relocation preserves the same six residents rather than adding more")
	watch_from_above()
	game.toggle_pause()
	var positions: Array[Vector3] = []
	for item: Dictionary in moved:
		positions.append(item.node.position)
	game.set_physics_process(true)
	for frame in range(5):
		await physics_frame
	game.set_physics_process(false)
	var frozen := true
	for index in range(moved.size()):
		frozen = frozen and moved[index].node.position == positions[index]
	check(frozen and game.state == "paused", "Real pause freezes all wreck patrols")
	game.toggle_pause()
	game.finish_dive(false)
	game.start_dive(false,false,2)
	check(residents().size() == 6 and game.fish.size() == 213, "Returning and diving again respawns six healthy residents without duplication")
