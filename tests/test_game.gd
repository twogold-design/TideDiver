extends SceneTree
## Full gameplay integration test. Uses in-memory progression and never touches saves.

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func save_game() -> void:
		saves += 1
	func load_game() -> void:
		pass

var failures: int = 0
var checks: int = 0
var game: Node
var memory: MemoryProgression

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._unhandled_input(event)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		printerr("FAIL: main scene could not load")
		quit(1)
		return
	game = packed.instantiate()
	memory = MemoryProgression.new()
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.smoke_mode = true
	_check(game.state == "dock", "Game starts at dock")
	_check(game.hud.buttons.size() == 7, "Dock has launch, three upgrades, restaurant, new game, and exit")
	game.start_dive()
	_check(game.state == "dive" and game.fish.size() == game.fish_population_count() and game.pickups.size() == 11 + game.Ocean.pickup_points().size(), "Starting a dive creates complete population")
	await physics_frame
	await process_frame
	_test_3d_controls_and_geometry()
	game.state = "dock"
	game.start_dive()
	_test_capacity_and_catching()
	_test_pause()
	_test_rescue()
	_test_return_and_upgrade()
	_test_restart()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	if failures == 0:
		print("PASS: Tide Diver gameplay integration (%d checks)." % checks)
	else:
		printerr("FAIL: %d / %d gameplay integration checks failed." % [failures, checks])
	quit(0 if failures == 0 else 1)

func _test_capacity_and_catching() -> void:
	game.cargo = [{"name": "Full bag", "value": 180, "weight": memory.capacity(), "kind": "fish"}]
	var pearl: Dictionary = game.pickups[0]
	game.player.position = pearl.node.position
	_key(KEY_F)
	_check(game.weight() == memory.capacity() and game.cargo.size() == 1, "Full bag rejects additional pearl")
	_check(pearl.active and pearl.node.visible, "Rejected pickup remains available")
	var bottle: Dictionary = game.pickups[9]
	game.oxygen = 10.0
	game.player.position = bottle.node.position
	_key(KEY_F)
	_check(game.oxygen == 45.0 and game.weight() == memory.capacity(), "Oxygen pickup works with a full bag")
	_check(not bottle.active and not bottle.node.visible, "Oxygen bottle consumed once")
	_key(KEY_F)
	_check(game.oxygen == 45.0, "Consumed oxygen bottle cannot be reused")
	for item in game.fish:
		item.alive = false
	var target: Dictionary = game.fish[0]
	target.alive = true
	target.hp = 1
	game.player.position = Vector3(0, -10, 10)
	game._update_dive(0.0)
	var center: Vector2 = root.get_visible_rect().size * 0.5
	target.node.position = game.camera.project_ray_origin(center) + game.camera.project_ray_normal(center) * 12.0
	_check(not game.target_fish().is_empty(), "Fish can be acquired at reticle")
	_key(KEY_SPACE)
	_check(game.cargo.size() == 1 and game.weight() == memory.capacity(), "Full bag rejects caught fish without overflow")
	_check(target.alive and target.hp == 1 and target.node.visible, "Fish remains available after full-bag rejection")
	game.cargo.clear()
	game.shot_cooldown = 0.0
	_key(KEY_SPACE)
	_check(game.cargo.size() == 1 and game.weight() == 1 and game.cargo_value() == 18, "Fish capture adds correct weight and value")
	_check(not target.alive and not target.node.visible, "Caught fish disappears exactly once")
	_key(KEY_SPACE)
	_check(game.cargo.size() == 1, "Shot cooldown prevents duplicate catch")

func _test_pause() -> void:
	_key(KEY_ESCAPE)
	_check(game.state == "paused" and game.hud.buttons.size() == 4, "Escape opens pause menu with new-game entry")
	var oxygen_before: float = game.oxygen
	var clock_before: float = game.clock
	var position_before: Vector3 = game.player.position
	var fish_before: Vector3 = game.fish[1].node.position
	game._physics_process(12.0)
	_check(game.oxygen == oxygen_before and game.clock == clock_before, "Pause freezes oxygen and simulation time")
	_check(game.player.position == position_before and game.fish[1].node.position == fish_before, "Pause freezes player and fish")
	game.player.position.y = -2.0
	_key(KEY_F)
	_check(game.state == "paused" and memory.day == 1, "Interaction cannot end a paused dive")
	_key(KEY_ESCAPE)
	_check(game.state == "dive" and game.hud.buttons.is_empty(), "Escape resumes exploration")
	game.player.position = position_before

func _test_rescue() -> void:
	game.cargo.clear()
	for i in range(10):
		game.cargo.append({"id": "orange", "value": 18, "weight": 1, "kind": "fish"})
	game.player.position = Vector3(40, -26, 40)
	game.oxygen = 0.01
	game._update_dive(1.0)
	_check(game.state == "dock" and game.last_result.rescued, "Empty oxygen triggers rescue to dock")
	_check(game.last_result.earned == 63 and memory.coins == 63, "Rescue settles exactly 35 percent")
	_check(game.cargo.is_empty() and memory.day == 2 and memory.saves == 1, "Rescue clears cargo, advances day, and persists once")
	_check(memory.best_depth == 26.0 and memory.total_fish == 10, "Rescue records depth and fish statistics")
	game.finish_dive(true)
	_check(memory.day == 2 and memory.coins == 63 and memory.saves == 1, "Duplicate settlement is ignored")

func _test_return_and_upgrade() -> void:
	game.start_dive()
	game.cargo = [{"id": "chest", "name": "Treasure", "value": 90, "weight": 3, "kind": "chest"}]
	game.player.position = Vector3(40, -4, 40)
	_key(KEY_F)
	_check(game.state == "dive", "F does not return to dock below surface threshold")
	game.player.position.y = -3.5
	_key(KEY_F)
	_check(game.state == "dock" and not game.last_result.rescued, "Surface F returns safely")
	_check(game.last_result.earned == 0 and memory.coins == 63 and memory.inventory.chest == 1 and memory.day == 3, "Safe return stores cargo without automatically selling it")
	game.open_restaurant()
	game.sell_goods("chest", 1)
	_check(memory.coins == 153 and memory.inventory.chest == 0, "Warehouse sale funds diving equipment")
	game.return_to_dock()
	game.upgrade("tank")
	_check(memory.tank_level == 1 and memory.coins == 73 and memory.oxygen_max() == 125.0, "Dock upgrade charges correct amount and improves equipment")
	game.upgrade("spear")
	_check(memory.spear_level == 0 and memory.coins == 73, "Unaffordable dock upgrade is rejected")

func _test_restart() -> void:
	game.start_dive()
	_check(game.oxygen == 125.0 and game.cargo.is_empty() and game.depth_record == 0.0, "New dive uses upgraded oxygen and resets cargo/depth")
	_check(game.player.position == Vector3(0, -6, 14) and game.player.visible, "New dive restores player spawn")
	_check(game.shot_cooldown == 0.0 and game.hurt_cooldown == 0.0, "New dive resets combat cooldowns")
	var all_fish_alive: bool = game.fish.size() == game.fish_population_count()
	for item in game.fish:
		all_fish_alive = all_fish_alive and item.alive and item.node.visible and item.hp == game.FishData.SPECIES[item.kind].hp
	var all_pickups_active: bool = game.pickups.size() == 11 + game.Ocean.pickup_points().size()
	for item in game.pickups:
		all_pickups_active = all_pickups_active and item.active and item.node.visible
	_check(all_fish_alive and all_pickups_active and game.hazards.size() == 7 + game.Ocean.ZONES.size(), "New dive regenerates fish, pickups, oxygen, and hazards")
	_check(memory.coins == 73 and memory.day == 3 and memory.tank_level == 1, "New dive retains persistent progress")
	_key(KEY_ESCAPE)
	game.hud._rescue()
	_check(game.state == "dock" and game.last_result.rescued and memory.day == 4, "Pause-menu rescue ends dive")


func _test_3d_controls_and_geometry() -> void:
	_check(game.player is CharacterBody3D, "Diver uses an actual 3D physics body")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var yaw_before: float = game.yaw
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(120.0, -40.0)
	game._unhandled_input(mouse)
	if DisplayServer.get_name() != "headless":
		_check(is_equal_approx(game.yaw, yaw_before - 120.0 * 0.0026), "Captured mouse motion rotates 3D heading")
	else:
		print("SKIP: Mouse capture requires display backend; run without --headless to verify.")
	mouse.relative = Vector2(0.0, -10000.0)
	game._unhandled_input(mouse)
	if DisplayServer.get_name() != "headless":
		_check(is_equal_approx(game.pitch, 1.10), "Mouse look clamps vertical pitch")
	game.yaw = 0.0
	game.pitch = -0.12
	game.player.position = Vector3(0.0, -6.0, 14.0)
	Input.action_press("ascend")
	game._physics_process(1.0 / 60.0)
	Input.action_release("ascend")
	_check(game.player.position.y > -6.0, "Ascend action moves diver upward in 3D")
	var raised_y: float = game.player.position.y
	Input.action_press("descend")
	game._physics_process(1.0 / 60.0)
	Input.action_release("descend")
	_check(game.player.position.y < raised_y, "Descend action moves diver downward in 3D")
	game.player.position = Vector3(0.0, game.Ocean.Y_MAX - 0.00001, 14.0)
	Input.action_press("ascend")
	game._physics_process(1.0 / 60.0)
	Input.action_release("ascend")
	_check(game.player.position.y <= game.Ocean.Y_MAX, "Upward swimming respects surface boundary")
	game.player.position = Vector3(0.0, game.Ocean.Y_MIN + 0.00001, 0.0)
	Input.action_press("descend")
	game._physics_process(1.0 / 60.0)
	Input.action_release("descend")
	_check(game.player.position.y >= game.Ocean.Y_MIN, "Downward swimming respects maximum-depth boundary")
	game.player.position = Vector3(game.Ocean.X_MAX - 0.00001, -4.0, 0.0)
	Input.action_press("swim_right")
	game._physics_process(1.0 / 60.0)
	Input.action_release("swim_right")
	_check(game.player.position.x <= game.Ocean.X_MAX, "Horizontal swimming respects ocean boundary")
	var collision := KinematicCollision3D.new()
	var floor_blocked: bool = game.player.test_move(Transform3D(Basis.IDENTITY, Vector3(0.0, -6.0, 0.0)), Vector3(0.0, -180.0, 0.0), collision)
	_check(floor_blocked, "Swept diver collider cannot pass through the solid seabed")
	if floor_blocked:
		_check(collision.get_normal().y > 0.9 and collision.get_travel().length() < 180.0, "Seabed collision stops downward movement before full travel")
		_check(absf(collision.get_position().y-game.Ocean.seabed_height(collision.get_position().x,collision.get_position().z)) < 0.1, "Collision hits the real world seabed, not a test fixture")
	var paused_position: Vector3 = game.player.position
	var paused_oxygen: float = game.oxygen
	game.toggle_pause()
	Input.action_press("descend")
	Input.action_press("swim_forward")
	game._physics_process(3.0)
	Input.action_release("descend")
	Input.action_release("swim_forward")
	_check(game.player.position == paused_position and game.oxygen == paused_oxygen, "Paused simulation ignores held movement and preserves oxygen")
	game.toggle_pause()
	_test_rock_occlusion()

func _test_rock_occlusion() -> void:
	# First authored reef: (8, -11, -2), rock center lowered by 5.3 * 0.32.
	# Fixed authored geometry keeps this independent of randomized fish positions.
	for item in game.fish:
		item.alive = false
	var target: Dictionary = game.fish[0]
	target.alive = true
	target.hp = 1
	target.node.visible = true
	game.player.position = Vector3(0.0, -8.0, 14.0)
	var rock_y: float = -11.0 - 5.3 * 0.32
	game.player.position = Vector3(8.0, rock_y, 7.0)
	game.camera.position = Vector3(8.0, rock_y, 8.0)
	target.node.position = Vector3(8.0, rock_y, -12.0)
	game.camera.look_at(target.node.position)
	var query := PhysicsRayQueryParameters3D.create(game.camera.position, target.node.position, 1, [game.player.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "Authored reef physically blocks the sight ray")
	_check(game.target_fish().is_empty(), "Fish behind solid reef cannot be targeted")
	var cargo_before: int = game.cargo.size()
	game.shot_cooldown = 0.0
	game.shoot()
	_check(target.alive and target.hp == 1 and game.cargo.size() == cargo_before, "Harpoon cannot damage or capture fish through reef")
	game.camera.position.x = 22.0
	game.player.position.x = 22.0
	target.node.position.x = 22.0
	game.camera.look_at(target.node.position)
	_check(not game.target_fish().is_empty(), "Same fish becomes targetable along an unobstructed sight ray")

