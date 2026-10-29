extends SceneTree
## Actual GM menu, button callbacks and destination geometry, with memory progress only.
const Ocean = preload("res://scripts/ocean_config.gd")

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
	memory.persistence_enabled = false
	memory.coins = 321
	memory.day = 7
	memory.inventory.orange = 2
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	_test_dock_menu_and_rejections()
	_test_cancel_and_input_isolation()
	await _test_destination_buttons()
	_test_modal_guards()
	_test_normal_random_departures()
	_check(memory._save_data() == progress_before and memory.saves == 0, "GM selection and cancellation neither mutate durable progress nor write a save")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver GM dive menu (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _buttons_containing(label: String) -> Array[Button]:
	var found: Array[Button] = []
	for button in game.hud.buttons:
		if button.text.contains(label):
			found.append(button)
	return found

func _test_dock_menu_and_rejections() -> void:
	var initial_position: Vector3 = game.player.position
	game.gm_select_dive_site(0, true)
	_check(game.state == "dock" and not game.gm_menu_open and game.player.position == initial_position, "Unsolicited selection cannot launch or teleport without an open GM menu")
	var launchers: Array[Button] = _buttons_containing("GM")
	_check(launchers.size() == 1 and not launchers[0].disabled, "The actual dock HUD exposes one enabled GM button")
	if not launchers.is_empty():
		launchers[0].pressed.emit()
	_check(game.gm_menu_open and game.gm_return_state == "dock" and game.state == "dock" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The dock GM button opens the menu without beginning a dive")
	_check(_buttons_containing("船上入水").size() == 6 and _buttons_containing("直达景观").size() == 6, "The real menu offers both launch modes for all six destinations")
	var expected_ids := ["tidal_cove","twin_gates","merchant_wreck","amber_reef","southern_spires","pearl_atoll"]
	var actual_ids: Array = []
	for site: Dictionary in Ocean.DIVE_SITES:
		actual_ids.append(site.id)
	_check(actual_ids == expected_ids and Ocean.site_index("lantern_garden") == -1, "Only the six retained destinations remain selectable in their intended order")
	_check(game.ocean_root.get_node_or_null("OuterOcean/lantern_garden") == null and Ocean.zone_for_position(Vector3(35,-82,-360)).is_empty(), "The removed garden has no remaining scene or navigation region")
	game.gm_select_dive_site(-1, true)
	game.gm_select_dive_site(Ocean.DIVE_SITES.size(), false)
	_check(game.gm_menu_open and game.state == "dock" and game.player.position == initial_position and not game.gm_test_active, "Negative and out-of-range indices leave the menu and game unchanged")
	game.request_new_game()
	_check(game.gm_menu_open and not game.new_game_confirmation, "The GM panel cannot open the destructive new-game modal at the same time")
	_key(KEY_ESCAPE)
	_check(not game.gm_menu_open and game.state == "dock" and game.player.position == initial_position, "Escape cancels a dock selection without starting or moving the diver")
	_key(KEY_F1)
	_check(game.gm_menu_open, "F1 opens the GM menu from the dock")
	_key(KEY_F1)
	_check(not game.gm_menu_open and game.state == "dock", "F1 closes the menu and restores the dock")

func _test_cancel_and_input_isolation() -> void:
	game.start_dive(false, false)
	game.cargo = [{"id":"orange", "name":"橘鳍鱼", "kind":"fish", "weight":1, "value":18}]
	game.oxygen = 47
	game.depth_record = 31
	game._update_dive(0)
	game.shoot()
	_check(game.projectiles.size() == 1, "The test opens GM while a real hook is airborne")
	_key(KEY_F1)
	_check(game.gm_menu_open and game.gm_return_state == "dive" and game.state == "paused" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Opening GM during a dive pauses exploration and releases the mouse")
	var position_before: Vector3 = game.player.position
	var air_before: float = game.oxygen
	var clock_before: float = game.clock
	var yaw_before: float = game.yaw
	var cargo_before: Array = game.cargo.duplicate(true)
	var projectile_before: Vector3 = game.projectiles[0].node.position if not game.projectiles.is_empty() else Vector3.ZERO
	_key(KEY_SPACE)
	_key(KEY_F)
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(100, 80)
	game._unhandled_input(mouse)
	game._physics_process(2)
	_check(game.state == "paused" and game.gm_menu_open and game.player.position == position_before and game.oxygen == air_before and game.clock == clock_before and game.yaw == yaw_before and game.cargo == cargo_before and game.projectiles.size() == 1 and game.projectiles[0].node.position == projectile_before, "GM consumes gameplay input and freezes the diver, air, time, cargo and airborne hook")
	game.close_gm_menu()
	_check(not game.gm_menu_open and game.state == "dive" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and game.cargo == cargo_before and game.oxygen == air_before, "Closing an in-dive menu restores exploration and preserves the existing dive")
	_key(KEY_ESCAPE)
	var pause_buttons: Array[Button] = _buttons_containing("GM")
	_check(game.state == "paused" and pause_buttons.size() == 1, "The actual pause menu also exposes a GM entry")
	if not pause_buttons.is_empty():
		pause_buttons[0].pressed.emit()
	_check(game.gm_menu_open and game.gm_return_state == "paused", "The pause-menu button records the existing paused state")
	_key(KEY_ESCAPE)
	_check(not game.gm_menu_open and game.state == "paused" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Cancelling a menu opened while paused keeps the dive paused")
	_key(KEY_ESCAPE)
	game._clear_projectiles()
	game.state = "dock"

func _test_destination_buttons() -> void:
	var harvested_fish_id: int = -1
	var harvested_pickup_id: int = -1
	for index in range(Ocean.DIVE_SITES.size()):
		_key(KEY_F1)
		var boat_buttons: Array[Button] = _buttons_containing("船上入水")
		_check(boat_buttons.size() == 6, "All six boat callbacks remain available for site %d" % index)
		if boat_buttons.size() != 6:
			return
		var cargo_before: Array = game.cargo.duplicate(true)
		var air_before: float = game.oxygen
		var day_before: int = memory.day
		var depth_before: float = game.depth_record
		var launching_from_dock: bool = game.gm_return_state == "dock"
		boat_buttons[index].pressed.emit()
		await process_frame
		var origin: Vector3 = game.dive_origin
		var base: Vector3 = Ocean.DIVE_SITES[index].origin
		_check(not game.gm_menu_open and game.gm_test_active and game.state == "dive" and game.entry_active and game.entry_site_index == index and origin.is_equal_approx(base), "The real boat button selects its exact named origin without random jitter: %d" % index)
		_check(game.player.position.is_equal_approx(origin + Vector3(0, 2.4, 17.5)) and game.boat.position.is_equal_approx(origin + Vector3(0, 0.3, 14)), "The selected boat and jump relocate together: %d" % index)
		if launching_from_dock:
			_check(game.cargo.is_empty() and game.oxygen == memory.oxygen_max() and memory.day == day_before and game.depth_record == 0, "A dock selection begins a fresh test dive without advancing the day")
		else:
			_check(game.cargo == cargo_before and game.oxygen == air_before and memory.day == day_before and game.depth_record == depth_before, "Selecting another boat during a dive preserves cargo, remaining air, day and explored depth: %d" % index)
			_check(_harvest_preserved(harvested_fish_id, harvested_pickup_id), "Boat transfer keeps the same harvested fish and pickup nodes unavailable: %d" % index)
		game._physics_process(3.2)
		_check(not game.entry_active and game.player.position.is_equal_approx(origin + Vector3(0, -6, 25)), "The selected boat mode completes the real submerged entry: %d" % index)
		if launching_from_dock:
			game.cargo = [{"id":"orange", "name":"橘鳍鱼", "kind":"fish", "weight":1, "value":18}]
			game.oxygen = 43
			game.depth_record = 31
			game.fish[0].alive = false
			game.fish[0].node.visible = false
			harvested_fish_id = game.fish[0].node.get_instance_id()
			game.pickups[0].active = false
			game.pickups[0].node.visible = false
			harvested_pickup_id = game.pickups[0].node.get_instance_id()
		game._clear_projectiles()
		game.shot_cooldown = 0
		game.shoot()
		game.drift_current = Vector3(0, 0, 0.9)
		game.current_hint = "test current"
		game.toggle_pause()
		_key(KEY_F1)
		var direct_buttons: Array[Button] = _buttons_containing("直达景观")
		_check(direct_buttons.size() == 6, "All six direct-test callbacks remain available for site %d" % index)
		if direct_buttons.size() != 6:
			return
		cargo_before = game.cargo.duplicate(true)
		air_before = game.oxygen
		day_before = memory.day
		depth_before = game.depth_record
		var expected: Dictionary = game._gm_test_pose(index)
		direct_buttons[index].pressed.emit()
		await process_frame
		_check(not game.gm_menu_open and game.gm_test_active and game.state == "dive" and not game.entry_active and game.entry_site_index == index and game.player.position.is_equal_approx(expected.position), "The actual direct-test button resumes at its own specified pose: %d" % index)
		_check(game.cargo == cargo_before and game.oxygen == air_before and memory.day == day_before and game.depth_record == depth_before, "Direct transfer preserves the existing catch, air, day and explored depth: %d" % index)
		_check(_harvest_preserved(harvested_fish_id, harvested_pickup_id), "Direct transfer keeps the same harvested fish and pickup nodes unavailable: %d" % index)
		_check(game.projectiles.is_empty() and game.drift_current.is_zero_approx() and game.current_hint.is_empty(), "Transfer clears old airborne hooks and the previous site's current: %d" % index)
		_check(_sphere_clear(game.player.position, 0.65) and game.player.position.y >= Ocean.seabed_height(game.player.position.x, game.player.position.z) + 0.65, "The actual direct-test pose is open water above the physical seabed: %d" % index)
		_check(_landmark_visible(index), "The direct-test camera can see its destination's characteristic scenery: %d" % index)
		if index == 1:
			_check(Ocean.current_velocity(game.player.position).length() > 0.3, "The canyon direct-test pose is deep enough to try the current immediately")

func _harvest_preserved(fish_id: int, pickup_id: int) -> bool:
	var fish_preserved: bool = false
	for item in game.fish:
		if item.node.get_instance_id() == fish_id:
			fish_preserved = not item.alive and not item.node.visible
	var pickup_preserved: bool = false
	for item in game.pickups:
		if item.node.get_instance_id() == pickup_id:
			pickup_preserved = not item.active and not item.node.visible
	return fish_preserved and pickup_preserved

func _landmark_visible(index: int) -> bool:
	if index == 0:
		return _visible_mesh(game.ocean_root)
	if Ocean.DIVE_SITES[index].id == "southern_spires":
		return game.storm_school.is_visible_in_tree() and game.camera.is_position_in_frustum(game.storm_school.global_position)
	var region: Node3D = game.ocean_root.get_node_or_null("OuterOcean/" + str(Ocean.ZONES[index - 1].id))
	return region != null and _visible_mesh(region)

func _visible_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree() and game.camera.is_position_in_frustum(node.global_transform * node.get_aabb().get_center()):
		return true
	if node is MultiMeshInstance3D and node.multimesh != null and node.is_visible_in_tree():
		for index in range(node.multimesh.instance_count):
			if game.camera.is_position_in_frustum(node.global_transform * node.multimesh.get_instance_transform(index).origin):
				return true
	for child in node.get_children():
		if _visible_mesh(child):
			return true
	return false

func _test_modal_guards() -> void:
	game.state = "dock"
	game.request_new_game()
	_key(KEY_F1)
	game.open_gm_menu()
	_check(game.new_game_confirmation and not game.gm_menu_open, "New-game confirmation rejects GM hotkeys and direct menu requests")
	_key(KEY_ESCAPE)
	game.open_restaurant()
	for state in ["restaurant", "service", "service_paused"]:
		game.state = state
		_key(KEY_F1)
		game.open_gm_menu()
		_check(not game.gm_menu_open and game.state == state, "Restaurant state does not open a competing GM panel: " + state)
	game.state = "restaurant"
	game.return_to_dock()

func _test_normal_random_departures() -> void:
	game.entry_rng.seed = 20261026
	var sites: Dictionary = {}
	var previous: int = -1
	var still_random: bool = true
	for departure in range(8):
		game.state = "dock"
		game.start_dive(false)
		still_random = still_random and game.entry_site_index >= 0 and game.entry_site_index < Ocean.DIVE_SITES.size() and game.entry_site_index != previous and not game.gm_test_active
		previous = game.entry_site_index
		sites[previous] = true
	_check(still_random and sites.size() > 1, "Ordinary departures remain random and clear the GM-test designation")

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
