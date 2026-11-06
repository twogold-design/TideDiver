extends SceneTree
## Real cave geometry, anchored moray encounters, swept harpoons and dive lifecycle.
const FishData = preload("res://scripts/fish_catalog.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const CaveArt = preload("res://scripts/crevice_art.gd")
const Harpoon = preload("res://scripts/harpoon.gd")

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

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	game.start_dive(false, false)
	await physics_frame
	await physics_frame
	var habitat: Node3D = game.crevice_habitat
	_check(is_instance_valid(habitat) and habitat.dens.size() >= 4, "Several real rock crevices host catchable morays")
	if not is_instance_valid(habitat) or habitat.dens.is_empty():
		game.free()
		quit(1)
		return
	_check(game.fish.size() == 183 and game.fish_population_count() == 183, "Rock-dwelling morays reuse the established 183-fish population")
	_test_natural_homes()
	var target: Dictionary = game.fish[habitat.dens[0].slot]
	_test_peeking(target)
	await _test_pause_and_gm(target)
	await _test_attack()
	await _test_obstruction()
	await _test_capture_and_lifecycle()
	await _test_clam()
	if DisplayServer.get_name() != "headless":
		await _capture_natural_caves()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver crevice morays and electric clam (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _head(item: Dictionary) -> Vector3:
	return item.node.to_global(item.node.get_meta("harpoon_center", Vector3(0, 0, -.75)))

func _forward(item: Dictionary) -> Vector3:
	return -item.den.global_basis.z.normalized()

func _clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [game.player.get_rid()])
	return game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _test_natural_homes() -> void:
	var valid := true
	var exposed := true
	var entrances := true
	var ground := true
	var safe_entries := true
	var sites: Dictionary = {}
	for den: Dictionary in game.crevice_habitat.dens:
		var item: Dictionary = game.fish[den.slot]
		valid = valid and item.kind == 7 and item.alive and item.den == den.node and item.hp == FishData.SPECIES[7].hp
		var head := _head(item)
		var forward := _forward(item)
		exposed = exposed and _clear(head + forward * 5.0, head)
		var mouth: Vector3 = den.node.to_global(den.node.get_meta("mouth", Vector3(0, 1.25, -1)))
		entrances = entrances and _clear(mouth + forward * 3.0, mouth - forward * .4)
		ground = ground and head.y < -2.0 and head.y > Ocean.seabed_height(head.x, head.z) + .2
		for site: Dictionary in Ocean.DIVE_SITES:
			safe_entries = safe_entries and head.distance_to(site.origin + Vector3(0, -6, 25)) > 20.0
		sites[den.site] = true
	_check(valid, "Every authored den has one healthy canonical moray linked to its normal capture slot")
	_check(exposed, "Every natural resting moray exposes its head to an unobstructed frontal harpoon ray")
	_check(entrances, "Rock walls surround actual open cave mouths rather than sealing their openings")
	_check(ground and safe_entries, "Moray heads lie underwater above the seabed and away from all entry landings")
	_check(sites.size() >= 3, "Crevice encounters are distributed across multiple dive sites")

func _step(item: Dictionary, seconds: float) -> void:
	var count := ceili(seconds * 60.0)
	for i in range(count):
		var delta := 1.0 / 60.0
		game.clock += delta
		game.hurt_cooldown = maxf(0, game.hurt_cooldown - delta)
		game._update_fish(item, delta)

func _test_peeking(item: Dictionary) -> void:
	game.player.position = _head(item) + _forward(item) * 12.0
	game.player.velocity = Vector3.ZERO
	game.oxygen = 100.0
	var rest: Vector3 = item.node.position
	var minimum := INF
	var maximum := -INF
	var anchored := true
	var jaw_moves := false
	var jaw: Node3D = item.node.get_node_or_null("Motion/Jaw")
	var initial_jaw: Transform3D = jaw.transform if jaw != null else Transform3D.IDENTITY
	for step in range(180):
		_step(item, .1)
		var reach: float = (item.node.position - rest).dot(_forward(item))
		minimum = minf(minimum, reach)
		maximum = maxf(maximum, reach)
		anchored = anchored and item.node.position.distance_to(rest) < 3.0
		jaw_moves = jaw_moves or (jaw != null and jaw.transform != initial_jaw)
	_check(maximum - minimum > .20 and anchored, "An undisturbed moray occasionally extends and retracts while staying attached to its cave")
	_check(jaw_moves, "The visible moray jaw breathes instead of remaining a static head")
	_check(game.oxygen == 100.0, "Watching a den from outside bite range does not consume air through attacks")

func _test_pause_and_gm(item: Dictionary) -> void:
	game.toggle_pause()
	var pose := _pose(item.node)
	var clock_before: float = game.clock
	var air_before: float = game.oxygen
	for step in range(15):
		game._physics_process(1.0 / 60.0)
	_check(game.state == "paused" and _pose(item.node) == pose and game.clock == clock_before and game.oxygen == air_before, "Pausing freezes the actual moray pose and simulation clock")
	game.open_gm_menu()
	for step in range(15):
		game._physics_process(1.0 / 60.0)
	_check(game.gm_menu_open and _pose(item.node) == pose and game.clock == clock_before, "The GM panel also freezes the rock encounter")
	game.close_gm_menu()
	game.toggle_pause()
	game.open_gm_menu()
	game.gm_select_dive_site(Ocean.site_index("amber_reef"), true)
	_check(game.state == "dive" and _pose(item.node) == pose and game.oxygen == air_before, "GM travel preserves the existing den and moray state")
	await physics_frame

func _fresh() -> Dictionary:
	game._spawn_population()
	await physics_frame
	await physics_frame
	game.state = "dive"
	game.entry_active = false
	game.gm_infinite_air = false
	game.oxygen = 100.0
	game.hurt_cooldown = 0.0
	game.poison_timer = 0.0
	game.hunt_warning = ""
	game.cargo.clear()
	game._clear_projectiles()
	var target: Dictionary = game.fish[game.crevice_habitat.dens[0].slot]
	game.player.position = _head(target) + _forward(target) * 1.0
	game.player.velocity = Vector3.ZERO
	return target

func _test_attack() -> void:
	var target: Dictionary = await _fresh()
	_step(target, 1.5)
	_check(game.oxygen == 88.0 and game.poison_timer == 0.0, "A close diver in front of the exposed head receives one twelve-air bite without venom")
	_check(game.hurt_flash > 0.0 and game.hunt_warning.contains("海鳗"), "A moray bite produces a named warning and injury flash")
	_step(target, 1.0)
	_check(game.oxygen == 88.0, "Moray attack recovery prevents repeated bites every simulation frame")
	game.player.position = _head(target) + _forward(target) * 10.0
	_step(target, 6.0)
	_check(target.node.position.distance_to(target.home) < 3.0 and game.oxygen == 88.0, "A departing diver is not chased into open water by a cave resident")
	target = await _fresh()
	game.entry_active = true
	_step(target, 2.0)
	_check(game.oxygen == 100.0, "Morays cannot damage the diver during the entry animation")
	game.entry_active = false
	game.state = "dock"
	_step(target, 2.0)
	_check(game.oxygen == 100.0, "Dock-time scenic animation cannot cause moray damage")
	game.state = "dive"
	target.alive = false
	_step(target, 2.0)
	_check(game.oxygen == 100.0, "Already caught morays cannot bite again")
	target = await _fresh()
	game.player.position = target.den.to_global(Vector3(2.0, 1.25, -1.35))
	_step(target, 2.0)
	_check(game.oxygen == 100.0, "A diver beside the rock does not trigger a frontal bite through its side wall")

func _test_obstruction() -> void:
	var target: Dictionary = await _fresh()
	var head := _head(target)
	var forward := _forward(target)
	var wall := StaticBody3D.new()
	game.add_child(wall)
	wall.global_transform = Transform3D(target.den.global_basis, head + forward * .5)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, .15)
	collider.shape = shape
	wall.add_child(collider)
	await physics_frame
	await physics_frame
	_step(target, 2.0)
	_check(game.oxygen == 100.0, "A real stone barrier blocks near-range biting through a wall")
	wall.free()
	await physics_frame
	_step(target, 1.5)
	_check(game.oxygen == 88.0, "Removing that barrier permits a bite from the same near position")

func _test_capture_and_lifecycle() -> void:
	var target: Dictionary = await _fresh()
	for item: Dictionary in game.fish:
		item.alive = item == target
		item.node.visible = item == target
	game.progress.spear_level = 3
	var head := _head(target)
	game.player.position = head + _forward(target) * 5.0
	game.camera.position = game.player.position
	game.camera.look_at(head)
	var direction: Vector3 = (head - game.player.position).normalized()
	game.yaw = atan2(-direction.x, -direction.z)
	game.shot_cooldown = 0.0
	var tail_start: Vector3 = target.node.to_global(Vector3(-.55, 0, 1.2))
	var tail_shot: Dictionary = Harpoon.launch(game, tail_start, target.node.global_basis.x.normalized())
	Harpoon.step(game, tail_shot, .04)
	Harpoon.dispose(tail_shot)
	_check(target.hp == FishData.SPECIES[7].hp and target.alive, "A hook crossing the hidden tail cannot trigger the moray's exposed-head hit volume")
	_check(game.target_fish() == target, "Aiming at the exposed head acquires the real den moray through the open mouth")
	game.shoot()
	var launched: bool = game.projectiles.size() == 1
	for step in range(90):
		game._update_projectiles(1.0 / 60.0)
	_check(launched and not target.alive and not target.node.visible and game.cargo.size() == 1, "The visible physical harpoon captures a natural den moray without passing through rock")
	_check(game.cargo.size() == 1 and game.cargo[0].id == "moray" and game.cargo[0].weight == FishData.SPECIES[7].weight, "Den catches use normal moray cargo, weight and capture feedback")
	var captured_node: Node3D = target.node
	_step(target, 10.0)
	game.open_gm_menu()
	game.gm_select_dive_site(Ocean.site_index("pearl_atoll"), true)
	_check(not target.alive and target.node == captured_node and not target.node.visible and game.cargo.size() == 1, "Caught cave residents stay absent during the dive and after GM travel")
	game.finish_dive(false)
	_check(game.progress.inventory.get("moray", 0) == 1, "Returning safely stores a caught den moray in the existing warehouse")
	game.start_dive(false, false)
	await physics_frame
	await physics_frame
	var fresh := true
	for den: Dictionary in game.crevice_habitat.dens:
		var item: Dictionary = game.fish[den.slot]
		fresh = fresh and item.alive and item.hp == FishData.SPECIES[7].hp
	_check(fresh and game.fish.size() == 183, "A new dive restores healthy den residents without duplicating fish")

func _test_clam() -> void:
	var cave: Node3D = game.crevice_habitat.clam_den
	_check(is_instance_valid(cave), "One authored cave contains the ornamental electric clam")
	if not is_instance_valid(cave):
		return
	_check(game.crevice_habitat.find_children("LightningClam", "Node3D", true, false).size() == 1, "Exactly one electric clam exists in the authored habitat group")
	var is_ornamental := true
	for item: Dictionary in game.fish:
		is_ornamental = is_ornamental and not cave.is_ancestor_of(item.node)
	for item: Dictionary in game.pickups:
		is_ornamental = is_ornamental and not cave.is_ancestor_of(item.node)
	_check(is_ornamental, "The electric clam is absent from catchable fish and collectible item lists")
	CaveArt.animate_clam(cave, .1)
	var first := _pose(cave)
	CaveArt.animate_clam(cave, 1.4)
	_check(_pose(cave) != first, "The ornamental clam has an animated mantle or tentacles inside the stone cavity")
	var forward: Vector3 = -cave.global_basis.z.normalized()
	var mouth: Vector3 = cave.to_global(cave.get_meta("mouth", Vector3(0, 1.25, -1)))
	_check(_clear(mouth + forward * 3.0, mouth), "The viewing approach to the electric-clam cave is physically open")
	game.player.position = mouth + forward * 3.0
	_check(game.crevice_habitat.observation(game).contains("闪电贝"), "Approaching the viewing cave identifies its ornamental electric clam")

func _capture_natural_caves() -> void:
	var directory := ProjectSettings.globalize_path("res://../.runtime/crevice-life")
	DirAccess.make_dir_recursive_absolute(directory)
	# Isolated behavior tests step only fish. Expire the earlier catch flourish
	# before recording new-dive residents, so it cannot look like a second eel.
	game._update_effects(2.0)
	await process_frame
	game.hud.visible = false
	game.player.get_child(0).visible = false
	var count := 0
	for den: Dictionary in game.crevice_habitat.dens:
		var cave: Node3D = den.node
		var item: Dictionary = game.fish[den.slot]
		game.player.position = cave.to_global(Vector3(0, 1.8, -5.5))
		game.camera.position = cave.to_global(Vector3(.3, 2.0, -7.0))
		game.camera.look_at(cave.to_global(Vector3(0, 1.45, -.25)))
		game._apply_underwater_lighting(-game.camera.position.y)
		game.crevice_habitat.animate(game.clock, game.player.position)
		game._update_fish(item, .016)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		var filename := "moray-site%d-slot%d.png" % [den.site, den.slot]
		_check(not frame.is_empty() and frame.save_png(directory.path_join(filename)) == OK, "Actual GPU frame of natural moray cave %d is available for visual review" % int(den.slot))
		count += 1
	var cave: Node3D = game.crevice_habitat.clam_den
	if is_instance_valid(cave):
		game.player.position = cave.to_global(Vector3(0, 1.5, -3.8))
		game.camera.position = cave.to_global(Vector3(-.3, 1.3, -4.4))
		game.camera.look_at(cave.to_global(Vector3(0, .8, -.15)))
		game._apply_underwater_lighting(-game.camera.position.y)
		game.crevice_habitat.animate(1.4, game.player.position)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		_check(not frame.is_empty() and frame.save_png(directory.path_join("electric-clam-cave.png")) == OK, "An actual underwater GPU frame shows the electric clam within its natural stone pocket")
	print("Cave screenshots: %s (%d moray caves and one clam cave)" % [directory, count])

func _pose(node: Node) -> Array:
	var result: Array = []
	if node is Node3D:
		result.append(node.transform)
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		result.append(node.material_override.emission_energy_multiplier)
	for child in node.get_children():
		result.append_array(_pose(child))
	return result
