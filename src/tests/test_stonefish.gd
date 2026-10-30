extends SceneTree
## Grounded camouflage, real contact/LOS, poison, physical captures and lifecycle isolation.
const Ocean = preload("res://scripts/ocean_config.gd")
const FishData = preload("res://scripts/fish_catalog.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const CALM := Vector3(400, -20, 400)

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var memory: MemoryProgression
var checks := 0
var failures := 0
var output: String

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
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
	output = ProjectSettings.globalize_path("res://../.runtime/stonefish-checks")
	DirAccess.make_dir_recursive_absolute(output)
	var before: Dictionary = memory._save_data().duplicate(true)
	var actual: Array[Dictionary] = _stonefish()
	_check(FishData.SPECIES.size() == 14 and FishData.SPECIES[9].id == "stonefish" and FishData.SPECIES[9].behavior == "camouflage", "Stonefish is the tenth canonical catch with stationary camouflage behavior")
	_check(actual.size() == 12 and game.stonefish_count == actual.size() and game.fish.size() == 171 and game.fish_population_count() == 171, "Twelve stonefish replace ordinary population slots while retaining exactly 171 huntable fish")
	if actual.size() == 12:
		_test_natural_homes(actual)
		await _test_grounded_idle_and_rendering(actual[0])
		_test_natural_physical_capture(actual[0])
		await _test_contact_poison_and_recovery()
		await _test_contact_obstruction()
		await _test_pause_and_gm()
		_test_inactive_damage_guards()
		_check(memory._save_data() == before and memory.saves == 0 and game.cargo.is_empty(), "Camouflage, contact damage, poison and GM inspection never mutate or save durable progress")
		await _test_physical_capture_and_persistence()
		_test_fresh_dive_and_new_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver rock-camouflaged stonefish (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _stonefish() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in game.fish:
		if int(item.kind) == 9:
			found.append(item)
	return found

func _test_natural_homes(actual: Array[Dictionary]) -> void:
	var grounded := true
	var rock_neighbors := true
	var clear := true
	var entry_safe := true
	var sites: Dictionary = {}
	for item: Dictionary in actual:
		var home: Vector3 = item.home
		var floor_y: float = Ocean.seabed_height(home.x, home.z)
		grounded = grounded and absf(home.y - floor_y - 0.035) < 0.015 and item.node.position.distance_to(home) < 0.01 and item.state == "camouflaged" and item.node.basis.y.dot(Vector3.UP) > 0.8
		var site: int = int(item.get("stonefish_site", -1))
		sites[site] = int(sites.get(site, 0)) + 1
		if not item.has("rock_anchor") or not item.has("rock_bounds"):
			rock_neighbors = false
		else:
			var anchor: Vector3 = item.rock_anchor
			var bounds: AABB = item.rock_bounds
			var nearest := Vector3(clampf(home.x, bounds.position.x, bounds.end.x), clampf(home.y, bounds.position.y, bounds.end.y), clampf(home.z, bounds.position.z, bounds.end.z))
			rock_neighbors = rock_neighbors and bounds.size.length() > 1.0 and bounds.grow(0.05).has_point(anchor) and home.distance_to(nearest) < 4.5
		var center: Vector3 = item.node.global_transform * Vector3(0, 0.25, 0)
		clear = clear and _sphere_clear(center, 0.12)
		for destination: Dictionary in Ocean.DIVE_SITES:
			entry_safe = entry_safe and home.distance_to(destination.origin + Vector3(0, -6, 25)) > 20.0
	var balanced: bool = sites.size() == 6
	for site in range(Ocean.DIVE_SITES.size()):
		balanced = balanced and int(sites.get(site, 0)) == 2
	_check(grounded, "Every real stonefish starts motionless on its actual sloping seabed instead of floating above it")
	_check(rock_neighbors and balanced, "Two stonefish per dive site occupy the edges of actual rock geometry")
	_check(clear, "Natural stonefish bodies are outside actual solid rocks and terrain")
	_check(entry_safe, "All natural stonefish leave clear space around every boat-entry landing")

func _test_grounded_idle_and_rendering(item: Dictionary) -> void:
	game.player.position = item.home + Vector3(0, 2.6, 4)
	game.player.velocity = Vector3.ZERO
	var before: Vector3 = item.node.position
	await _physics_frames(90)
	_check(item.node.position.distance_to(before) < 0.015 and item.state == "camouflaged" and not item.alerted, "A nearby diver does not make the camouflaged stonefish pursue, flee or drift in real physics frames")
	game.camera.position = item.home + Vector3(3.3, 2.2, 4.0)
	game.camera.look_at(item.home + Vector3.UP * 0.25)
	await process_frame
	await RenderingServer.frame_post_draw
	var meshes: Array[Node] = item.node.find_children("*", "MeshInstance3D", true, false)
	var visible := false
	var vertices := 0
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh != null:
			vertices += mesh.mesh.surface_get_array_len(0)
			visible = visible or (mesh.is_visible_in_tree() and game.camera.is_position_in_frustum(mesh.global_transform * mesh.get_aabb().get_center()))
	var frame: Image = root.get_texture().get_image()
	_check(visible and vertices >= 60 and not frame.is_empty(), "The original rock-like stonefish model is present in an actual close GPU frame")
	_check(frame.save_png(output.path_join("stonefish-camouflaged.png")) == OK, "A rendered natural rock-edge stonefish frame is available for visual review")
	_check(item.node.get_node("RockBody").material_override == Geology.rock_material() and item.node.get_node("Spines/DorsalSpines").material_override == Geology.rock_material(), "The real stonefish body and dorsal spines share the surrounding rocks' actual material")

func _test_natural_physical_capture(target: Dictionary) -> void:
	var alive_flags: Array[bool] = []
	var visible_flags: Array[bool] = []
	for item: Dictionary in game.fish:
		alive_flags.append(item.alive)
		visible_flags.append(item.node.visible)
		item.alive = item == target
		item.node.visible = item == target
	var original: Dictionary = target.duplicate()
	var level_before: int = memory.spear_level
	memory.spear_level = 3
	var body_center: Vector3 = target.node.to_global(target.node.get_meta("harpoon_center"))
	var usable_pose := false
	for index in range(8):
		var angle: float = float(index) * TAU / 8.0
		var position: Vector3 = target.home + Vector3(sin(angle) * 5, 2, cos(angle) * 5)
		var direction: Vector3 = (body_center - position).normalized()
		var heading: float = atan2(-direction.x, -direction.z)
		var muzzle: Vector3 = position + Vector3(0.58, -0.15, -1.5).rotated(Vector3.UP, heading)
		var aim_ray := PhysicsRayQueryParameters3D.create(position, body_center, 1, [game.player.get_rid()])
		var muzzle_ray := PhysicsRayQueryParameters3D.create(muzzle, body_center, 1, [game.player.get_rid()])
		if _sphere_clear(position, 0.65) and game.get_world_3d().direct_space_state.intersect_ray(aim_ray).is_empty() and game.get_world_3d().direct_space_state.intersect_ray(muzzle_ray).is_empty():
			game.player.position = position
			game.player.velocity = Vector3.ZERO
			game.yaw = heading
			game.camera.position = position
			game.camera.look_at(body_center)
			usable_pose = true
			break
	game.shot_cooldown = 0
	var acquired: bool = usable_pose and game.target_fish() == target
	if usable_pose:
		game.shoot()
	var launched: bool = game.projectiles.size() == 1
	for step in range(60):
		game._update_projectiles(1.0 / 60.0)
	_check(acquired and launched and not target.alive and game.cargo.size() == 1 and game.cargo[0].id == "stonefish", "Aiming and firing at an untouched natural rock-edge stonefish actually captures its body above the seabed")
	target.clear()
	target.merge(original)
	for index in range(game.fish.size()):
		game.fish[index].alive = alive_flags[index]
		game.fish[index].node.visible = visible_flags[index]
	memory.spear_level = level_before
	game.cargo.clear()
	game._clear_projectiles()

func _fixture() -> Dictionary:
	var target: Dictionary = _stonefish()[0]
	for item: Dictionary in game.fish:
		item.alive = item == target
		item.node.visible = item == target
	for item: Dictionary in game.hazards:
		item.node.position = Vector3(-480, -100, 480)
		item.home = item.node.position
	game._clear_projectiles()
	game.cargo.clear()
	game.state = "dive"
	game.entry_active = false
	game.player.position = CALM + Vector3(0, 0.25, 2.0)
	game.player.velocity = Vector3.ZERO
	game.yaw = 0
	game.pitch = 0
	game.oxygen = 100
	game.poison_timer = 0
	game.hurt_cooldown = 0
	game.hunt_warning_timer = 0
	game.hunt_warning = ""
	game.hurt_flash = 0
	game.catch_timer = 0
	game.hit_timer = 0
	game.notice_timer = 0
	target.home = CALM
	target.node.position = CALM
	target.node.basis = Basis.IDENTITY
	target.previous_position = CALM
	target.state = "camouflaged"
	target.timer = 0.0
	target.hp = int(FishData.SPECIES[9].hp)
	target.armor = false
	target.alerted = false
	return target

func _test_contact_poison_and_recovery() -> void:
	var target := _fixture()
	await _physics_frames(1)
	_check(game.oxygen > 99.9 and game.poison_timer == 0 and target.state == "camouflaged", "Being close without touching the stonefish causes no contact injury or poison")
	game.player.position = CALM + Vector3(0, 0.25, 1.3)
	game.player.velocity = Vector3.ZERO
	game.oxygen = 100
	await _physics_frames(1)
	_check(game.oxygen <= 88.0 and game.oxygen > 87.8 and game.poison_timer > 5.9 and game.hurt_cooldown > 2.45, "A real diver-body contact costs twelve units of air, starts six seconds of poison and grants 2.5 seconds of immunity")
	_check(target.state == "exposed" and game.hunt_warning_timer > 0 and game.hunt_warning.contains("石头") and game.hurt_flash > 0 and absf(target.node.get_node("Spines").rotation.x) > 0.1, "Contact visibly raises the actual dorsal spines, flashes the screen and gives a named injury warning")
	game.camera.position = CALM + Vector3(-2, 1.8, -3)
	game.camera.look_at(CALM + Vector3.UP * 0.25)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join("stonefish-exposed.png")) == OK, "A rendered exposed-spine and contact-injury frame is available for visual review")
	var air_before: float = game.oxygen
	await _physics_frames(45)
	_check(air_before - game.oxygen > 1.0 and air_before - game.oxygen < 3.0 and game.hurt_cooldown > 1.6 and target.node.position.is_equal_approx(CALM), "Continued body contact during immunity adds poison and breathing only while the fish remains still")
	game.player.position = CALM + Vector3(0, 3, 10)
	game.player.velocity = Vector3.ZERO
	await _physics_frames(180)
	_check(target.state == "camouflaged" and target.node.position.is_equal_approx(CALM) and game.hurt_cooldown == 0, "After three seconds the exposed stonefish returns to camouflage at its unchanged home")
	air_before = game.oxygen
	game.player.position = CALM + Vector3(0, 0.25, 1.3)
	game.player.velocity = Vector3.ZERO
	await _physics_frames(1)
	_check(air_before - game.oxygen >= 12 and air_before - game.oxygen < 12.2 and game.poison_timer > 5.9, "A later genuine contact can injure the diver again after immunity expires")
	game.player.position = CALM + Vector3(0, 3, 10)
	game.player.velocity = Vector3.ZERO
	await _physics_frames(365)
	_check(game.poison_timer == 0 and target.state == "camouflaged", "Contact poison expires after its six-second duration instead of persisting indefinitely")

func _test_contact_obstruction() -> void:
	var target := _fixture()
	game.player.position = CALM + Vector3(0, 0.25, 1.3)
	var wall := StaticBody3D.new()
	wall.position = CALM + Vector3(0, 0.25, 0.5)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.15)
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	await _physics_frames(1)
	_check(game.oxygen > 99.9 and game.poison_timer == 0 and target.state == "camouflaged", "A thin real wall blocks venomous contact even when the expanded body volumes are close")
	wall.free()
	await physics_frame
	await _physics_frames(1)
	_check(game.oxygen < 88.1 and game.poison_timer > 5.9 and target.state == "exposed", "Removing the actual wall allows the same body position to trigger contact damage")

func _test_pause_and_gm() -> void:
	game.toggle_pause()
	var target: Dictionary = _stonefish()[0]
	var before := _snapshot(target)
	await _physics_frames(15)
	_check(game.state == "paused" and _snapshot(target) == before, "Pause freezes stonefish exposure, its actual model, poison, immunity and air in real physics frames")
	game.open_gm_menu()
	await _physics_frames(15)
	_check(game.gm_menu_open and _snapshot(target) == before, "The open GM panel freezes the same real exposed fish and injury timers")
	game.close_gm_menu()
	game.toggle_pause()
	game.open_gm_menu()
	var air_before: float = game.oxygen
	var position_before: Vector3 = target.node.position
	game.gm_select_dive_site(game.Ocean.site_index("amber_reef"), true)
	_check(game.state == "dive" and target.state == before.state and target.node.position == position_before and game.oxygen == air_before, "GM transfer preserves the current stonefish exposure, its home position and the remaining air")

func _test_inactive_damage_guards() -> void:
	var target := _fixture()
	game.player.position = CALM + Vector3(0, 0.25, 1.3)
	game.entry_active = true
	game._update_fish(target, 0.02)
	_check(game.oxygen == 100 and game.poison_timer == 0, "Stonefish cannot injure the diver while the boat-entry animation is active")
	game.entry_active = false
	game.state = "dock"
	game._update_fish(target, 0.02)
	_check(game.oxygen == 100 and game.poison_timer == 0, "Decorative dock-time animation cannot apply stonefish contact damage")
	game.state = "dive"
	target.alive = false
	game._update_fish(target, 0.02)
	_check(game.oxygen == 100 and game.poison_timer == 0, "An already caught stonefish cannot inflict further contact injury")

func _test_physical_capture_and_persistence() -> void:
	var target := _fixture()
	memory.spear_level = 3
	game.player.position = CALM + Vector3(0, 0.25, 8)
	game.camera.position = game.player.position
	game.camera.look_at(CALM + Vector3.UP * 0.25)
	game.yaw = 0
	game.shot_cooldown = 0
	game.shoot()
	var launched: bool = game.projectiles.size() == 1
	var travelled := 0.0
	for step in range(60):
		if not game.projectiles.is_empty():
			travelled = maxf(travelled, float(game.projectiles[0].distance))
		game._update_projectiles(1.0 / 60.0)
	_check(launched and travelled > 3 and not target.alive and not target.node.visible and game.cargo.size() == 1, "A real visible flying harpoon intersects and captures the grounded-origin stonefish body")
	var species: Dictionary = FishData.SPECIES[9]
	_check(game.cargo.size() == 1 and game.cargo[0].id == "stonefish" and game.cargo[0].weight == species.weight and game.cargo[0].value == species.value and game.catch_kind == 9 and game.catch_timer > 0, "Actual stonefish capture preserves canonical cargo and its own named capture feedback")
	game.shot_cooldown = 0
	game.shoot()
	for step in range(60):
		game._update_projectiles(1.0 / 60.0)
	_check(game.cargo.size() == 1, "A captured stonefish cannot be harvested twice by another physical hook")
	game.finish_dive(false)
	_check(memory.inventory.get("stonefish", 0) == 1 and memory.total_fish == 1 and game.cargo.is_empty(), "Safe return stores one real stonefish catch in the existing warehouse and fish statistics")
	var reloaded := MemoryProgression.new()
	reloaded.persistence_enabled = false
	reloaded._apply_save_data(memory._save_data().duplicate(true))
	_check(reloaded.inventory.get("stonefish", 0) == 1 and reloaded.total_fish == 1, "A save-data reload retains the stonefish as an ordinary canonical catch")
	var legacy := MemoryProgression.new()
	legacy.persistence_enabled = false
	legacy._apply_save_data({"version":4,"day":7,"coins":99,"inventory":{"orange":2}})
	_check(legacy.inventory.get("stonefish", -1) == 0 and legacy.inventory.orange == 2 and legacy.day == 7 and legacy.coins == 99, "Loading an old save initializes stonefish stock to zero while preserving existing progress")
	var save_text := JSON.stringify(memory._save_data()).to_lower()
	_check(not save_text.contains("camouflaged") and not save_text.contains("exposed") and not save_text.contains("rock_anchor"), "Temporary camouflage, rock placement and exposure state do not enter persistent saves")
	await process_frame

func _test_fresh_dive_and_new_game() -> void:
	game.start_dive(false, false)
	var reset := true
	for item: Dictionary in _stonefish():
		reset = reset and item.alive and item.hp == FishData.SPECIES[9].hp and item.state == "camouflaged" and item.node.position.is_equal_approx(item.home) and absf(item.home.y - Ocean.seabed_height(item.home.x, item.home.z) - 0.035) < 0.015
	_check(_stonefish().size() == 12 and reset and game.fish.size() == 171 and game.poison_timer == 0 and game.hurt_cooldown == 0, "A fresh dive restores twelve healthy rock-edge stonefish and clears old contact effects without increasing population")
	game.toggle_pause()
	game.request_new_game()
	game.confirm_new_game()
	reset = true
	for item: Dictionary in _stonefish():
		reset = reset and item.state == "camouflaged" and item.alive
	_check(game.state == "dock" and _stonefish().size() == 12 and reset and memory.inventory.get("stonefish", -1) == 0 and game.poison_timer == 0, "Confirmed new game resets both stonefish encounters and captured warehouse stock")

func _snapshot(item: Dictionary) -> Dictionary:
	return {"state":item.state,"timer":item.timer,"pose":_pose(item.node),"air":game.oxygen,"poison":game.poison_timer,"immunity":game.hurt_cooldown,"clock":game.clock}

func _pose(node: Node) -> Array:
	var result: Array = []
	if node is Node3D:
		result.append(node.transform)
	for child in node.get_children():
		result.append_array(_pose(child))
	return result

func _physics_frames(count: int) -> void:
	game.set_physics_process(true)
	await physics_frame
	for step in range(count):
		await physics_frame
	game.set_physics_process(false)

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
