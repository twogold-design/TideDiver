extends SceneTree
## Hunting integration uses memory progression; the only disk save is tests/temp/hunting.json.
const P = preload("res://scripts/progression.gd")
const FishData = preload("res://scripts/fish_catalog.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const TEST_PATH := "res://tests/temp/hunting.json"
class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1
var checks: int = 0
var failures: int = 0
var game: Node
var progress: MemoryProgression
func _init() -> void:
	call_deferred("_run")
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _run() -> void:
	_test_catalog_and_persistence()
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		printerr("FAIL: main scene could not load")
		quit(1)
		return
	game = scene.instantiate()
	progress = MemoryProgression.new()
	progress.persistence_enabled = false
	game.progress = progress
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	_test_population_and_seabed()
	_test_range_and_capture()
	_test_fish_reactions()
	_test_predators_and_poison()
	await _test_obstruction()
	_test_hunting_pause()
	_test_warehouse_pagination()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver hunting (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _clear_fixture() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
func _test_catalog_and_persistence() -> void:
	_check(FishData.SPECIES.size() == 9, "Hunting provides nine catalogued species")
	var ids: Dictionary = {}
	var cargo: Array = []
	var total_value: int = 0
	for species in FishData.SPECIES:
		_check(not ids.has(species.id) and P.GOODS.has(species.id) and P.GOODS[species.id].value == species.value, "Species is unique and has one canonical sale value: " + species.id)
		_check(species.hp > 0 and species.weight > 0 and species.speed > 0 and species.radius > 0, "Species combat and catch data are positive: " + species.id)
		ids[species.id] = true
		cargo.append({"id":species.id,"value":999999})
		total_value += int(species.value)
	var memory := MemoryProgression.new()
	memory.persistence_enabled = false
	memory.inventory = {"orange":0,"blue":0,"lantern":0,"pearl":0,"chest":0}
	var result: Dictionary = memory.complete_dive(cargo,false,115.0)
	_check(cargo.is_empty() and result.count == 9 and result.earned == 0 and memory.inventory_total() == 9 and memory.total_fish == 9, "All nine fish store once and count as fish even with legacy sparse inventory")
	for species in FishData.SPECIES:
		_check(memory.inventory.get(species.id,0) == 1, "Safe return stores actual species identity: " + species.id)
	_clear_fixture()
	var disk = P.new()
	disk.persistence_enabled = false
	disk._apply_save_data(memory._save_data().duplicate(true))
	disk.save_path = TEST_PATH
	disk.persistence_enabled = true
	disk.save_game()
	var loaded = P.new()
	loaded.save_path = TEST_PATH
	loaded.load_game()
	_check(loaded.inventory == memory.inventory and loaded.total_fish == 9 and loaded.best_depth == 115.0, "Actual isolated JSON reload retains every new fish and its catch statistics")
	var earned: int = 0
	for species in FishData.SPECIES:
		earned += memory.sell(species.id,1)
	_check(earned == total_value and memory.coins == total_value and memory.inventory_total() == 0, "Selling all nine kinds uses canonical prices rather than untrusted cargo values")
	for species in FishData.SPECIES:
		_check(memory.sell(species.id,1) == 0, "Sold fish cannot be sold twice: " + species.id)
	cargo.clear()
	for species in FishData.SPECIES:
		cargo.append({"id":species.id,"value":999999})
	result = memory.complete_dive(cargo,true,119.0)
	_check(result.earned == int(float(total_value*35)/100.0) and result.stored.is_empty() and memory.inventory_total() == 0 and memory.total_fish == 18, "Rescue settles all nine species at 35 percent and never duplicates warehouse stock")
	var legacy = P.new()
	legacy.persistence_enabled = false
	legacy._apply_save_data({"version":4,"coins":99,"day":7,"inventory":{"orange":2,"blue":1,"pearl":3},"last_service_result":{"served":1,"reviews":{"satisfied":1,"okay":0,"lost":0}}})
	_check(legacy.coins == 99 and legacy.day == 7 and legacy.inventory.orange == 2 and legacy.inventory.pearl == 3 and legacy.inventory.get("reef_shark",-1) == 0 and legacy.inventory.get("puffer",-1) == 0, "Existing V4 save preserves old progress and initializes new species at zero")
	legacy._apply_save_data({"inventory":{"reef_shark":-5,"moray":"7","tuna":3.5,"puffer":1.0e20,"unknown_fish":99}})
	_check(legacy.inventory.reef_shark == 0 and legacy.inventory.moray == 0 and legacy.inventory.tuna == 0 and legacy.inventory.puffer == P.MAX_ITEMS and not legacy.inventory.has("unknown_fish"), "New fish quantities retain save validation and bounds")
	_clear_fixture()
func _button_named(ui: Node, label: String) -> Button:
	for button in ui.buttons:
		if button.text == label:
			return button
	return null
func _press_named(ui: Node, label: String) -> void:
	var button := _button_named(ui,label)
	_check(button != null and not button.disabled, "Actual enabled UI button exists: " + label)
	if button != null and not button.disabled:
		button.pressed.emit()
func _test_warehouse_pagination() -> void:
	for species in FishData.SPECIES:
		progress.inventory[species.id] = 1
	game.open_restaurant()
	var ui: Node = game.hud.restaurant_ui
	_check(ui._warehouse_page_count() == 3 and ui.warehouse_page == 0 and ui._warehouse_ids() == ["orange","blue","lantern","pearl","chest"], "Warehouse first page preserves original fish and valuables")
	_check(_button_named(ui,"上一页").disabled, "First page cannot navigate below zero")
	_press_named(ui,"下一页")
	_check(ui.warehouse_page == 1 and ui._warehouse_ids() == ["sardine","puffer","lionfish","tuna","moray"], "Real next-page callback exposes five new catches")
	var before: int = progress.coins
	_press_named(ui,"卖 1 件")
	_check(progress.inventory.sardine == 0 and progress.inventory.puffer == 1 and progress.inventory.orange == 1 and progress.coins == before + 24, "Second-page sale callback is bound to displayed sardine rather than an old row")
	_press_named(ui,"下一页")
	_check(ui.warehouse_page == 2 and ui._warehouse_ids() == ["reef_shark"] and _button_named(ui,"下一页").disabled, "Third page exposes reef shark and disables further navigation")
	_press_named(ui,"全卖")
	_check(progress.inventory.reef_shark == 0 and progress.coins == before + 204, "Last-page sale pays reef shark value exactly once")
	_check(_button_named(ui,"全卖").disabled, "Sold-out last-page row cannot be sold again")
	ui._change_warehouse_page(100)
	_check(ui.warehouse_page == 2, "Page overflow clamps safely")
	ui._change_warehouse_page(-100)
	_check(ui.warehouse_page == 0, "Page underflow clamps safely")
	var seen: Dictionary = {}
	var rows_fit: bool = true
	for index in range(ui._warehouse_page_count()):
		ui.warehouse_page = index
		ui.rebuild()
		for id in ui._warehouse_ids():
			seen[id] = true
		for button in ui.buttons:
			if button.text in ["卖 1 件","全卖"]:
				rows_fit = rows_fit and button.position.y + button.size.y < 625
	_check(seen.size() == P.GOODS.size() and rows_fit, "Every warehouse good is reachable and sale rows fit above page controls")
	game.return_to_dock()

func _disable_fish() -> void:
	for item in game.fish:
		item.alive = false
		item.node.visible = false
func _fixture(kind: int, position: Vector3) -> Dictionary:
	for item in game.fish:
		if item.kind == kind and not item.alive:
			item.alive = true
			item.node.visible = true
			item.node.position = position
			item.home = position
			item.hp = int(FishData.SPECIES[kind].hp)
			item.state = "patrol"
			item.timer = 0.0
			item.direction = Vector3.FORWARD
			item.attack_cooldown = 0.0
			item.alerted = false
			item.armor = false
			item.node.scale = Vector3.ONE
			return item
	_check(false,"Required actual fish exists for fixture kind %d" % kind)
	return {}
func _aim_at(item: Dictionary) -> void:
	game.camera.position = game.player.position + Vector3(0,0,7.5)
	game.camera.look_at(item.node.position,Vector3.UP)
	game.shot_cooldown = 0.0
func _test_population_and_seabed() -> void:
	game.start_dive(false, false)
	_check(Ocean.X_MAX-Ocean.X_MIN >= 1000 and Ocean.Z_MAX-Ocean.Z_MIN >= 1000 and Ocean.Y_MIN <= -120, "Playable ocean spans a kilometre in both directions and reaches 120 metres")
	_check(game.fish.size() == 167, "Sparse ocean and entry schools create exactly 167 ordinary catchable fish")
	var kinds: Dictionary = {}
	var valid: bool = true
	var deepest: float = 0.0
	for item in game.fish:
		kinds[item.kind] = int(kinds.get(item.kind,0))+1
		valid = valid and item.alive and item.hp == FishData.SPECIES[item.kind].hp and item.home.y > Ocean.seabed_height(item.home.x,item.home.z)
		deepest = minf(deepest,item.home.y)
	_check(kinds.size() == 9 and valid, "All nine species spawn alive with canonical health above natural seabed")
	_check(deepest < -65, "Deep-water fish occupy habitats far below the starter cove")
	var heights: Array[float] = []
	for point: Vector2 in [Vector2(-480,-480),Vector2(480,-480),Vector2(-480,480),Vector2(480,480),Vector2(0,100),Vector2(80,-320)]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x,-2,point.y),Vector3(point.x,-150,point.y),1,[game.player.get_rid()])
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
		var expected: float = Ocean.seabed_height(point.x,point.y)
		heights.append(expected)
		_check(not hit.is_empty() and absf(hit.position.y-expected) < 0.03 and hit.normal.y > 0.3, "Actual terrain physics agrees with its natural height at " + str(point))
	_check(heights.max()-heights.min() > 20.0, "Natural seabed has meaningful shelf and canyon elevation changes")
func _test_range_and_capture() -> void:
	_disable_fish()
	game.player.position = Vector3(200,-8,200)
	var target := _fixture(0,game.player.position+Vector3(0,0,-19.9))
	_aim_at(target)
	_check(not game.target_fish().is_empty(), "Harpoon can acquire a fish 19.9 metres from the diver despite rear camera offset")
	target.node.position.z = game.player.position.z-20.1
	_aim_at(target)
	_check(game.target_fish().is_empty(), "Harpoon cannot acquire a fish beyond the diver's 20 metre range")
	var hp_before: int = target.hp
	game.shoot()
	_check(target.hp == hp_before and game.cargo.is_empty(), "Out-of-range shot cannot hurt or capture the target")
	_disable_fish()
	progress.spear_level = 3
	for kind in range(FishData.SPECIES.size()):
		game.cargo.clear()
		game.catch_timer = 0.0
		game.catch_kind = -1
		target = _fixture(kind,game.player.position+Vector3(0,0,-12))
		var species: Dictionary = FishData.SPECIES[kind]
		for shot in range(12):
			if not target.alive:
				break
			_aim_at(target)
			game.shoot()
		_check(not target.alive and not target.node.visible and game.cargo.size() == 1, "Real harpoon can capture species exactly once: " + species.id)
		_check(game.catch_timer > 0 and game.catch_kind == kind, "Every captured species triggers its own named catch feedback: " + species.id)
		if game.cargo.size() == 1:
			_check(game.cargo[0].id == species.id and game.cargo[0].weight == species.weight and game.cargo[0].value == species.value, "Actual catch retains canonical identity, weight and value: " + species.id)
		var count: int = game.cargo.size()
		game.shot_cooldown = 0
		game.shoot()
		_check(game.cargo.size() == count, "Captured target cannot be harvested twice: " + species.id)
	game.cargo.clear()
	progress.spear_level = 0
func _test_fish_reactions() -> void:
	_disable_fish()
	game.player.position = Vector3(200,-8,200)
	var cautious := _fixture(1,game.player.position+Vector3(0,0,-6))
	var distance_before: float = cautious.node.position.distance_to(game.player.position)
	game._update_fish(cautious,0.1)
	_check(cautious.state == "flee" and cautious.timer > 0 and cautious.node.position.distance_to(game.player.position) > distance_before, "Alert blue fish really flees away from an approaching diver")
	cautious.alive = false
	var stealth_fish := _fixture(1,game.player.position+Vector3(0,0,-6))
	Input.action_press("stealth")
	game._update_fish(stealth_fish,0.1)
	Input.action_release("stealth")
	_check(stealth_fish.state == "patrol", "Quiet approach reduces the actual fish detection distance")
	stealth_fish.node.position = game.player.position+Vector3(0,0,-10)
	stealth_fish.home = stealth_fish.node.position
	Input.action_press("boost")
	game._update_fish(stealth_fish,0.1)
	Input.action_release("boost")
	_check(stealth_fish.state == "flee", "Boosting startles fish from farther away")
	_disable_fish()
	var source := _fixture(1,game.player.position+Vector3(0,0,-12))
	var neighbor := _fixture(3,source.node.position+Vector3(3,0,0))
	var remote := _fixture(3,source.node.position+Vector3(30,0,0))
	game._hit_fish(source)
	_check(source.hp == 1 and source.state == "flee" and neighbor.state == "flee" and neighbor.timer > 0, "A real surviving hit alarms both the target and nearby school")
	_check(remote.state == "patrol", "Hit alarm stays local rather than startling the entire ocean")
	_disable_fish()
	var puffer := _fixture(4,game.player.position+Vector3(0,0,-5))
	game._update_fish(puffer,0.1)
	_check(puffer.state == "inflate" and puffer.armor and puffer.node.scale.x > 1.0, "Approached puffer visibly inflates and gains armor")
	progress.spear_level = 3
	game._hit_fish(puffer)
	_check(puffer.alive and puffer.hp == 2, "Inflated puffer absorbs all but one point of an upgraded spear hit")
	puffer.timer = 0.01
	game._update_fish(puffer,0.02)
	_check(puffer.state == "recover" and not puffer.armor and puffer.timer >= 3.9, "Puffer deflates into a real four-second vulnerable window")
	game.cargo.clear()
	game._hit_fish(puffer)
	_check(not puffer.alive and game.cargo.size() == 1 and game.cargo[0].id == "puffer", "Upgraded spear exploits the deflated puffer's vulnerable window")
	game.cargo.clear()
	progress.spear_level = 0
func _test_predators_and_poison() -> void:
	for kind: int in [7,8]:
		_disable_fish()
		game.player.position = Vector3(200,-8,200)
		game.oxygen = 100
		game.hurt_cooldown = 0
		var predator := _fixture(kind,game.player.position+Vector3(0,0,-8))
		game._update_fish(predator,0.1)
		_check(predator.state == "windup" and predator.timer > 1.0 and game.oxygen == 100 and game.hunt_warning_timer > 0 and not game.hunt_warning.is_empty(), "Predator gives readable warning before damage: " + FishData.SPECIES[kind].id)
		predator.timer = 0.01
		var prior: Vector3 = predator.node.position
		game._update_fish(predator,0.02)
		_check(predator.state == "charge" and predator.node.position.distance_to(prior) > 0.15, "Warning transitions to a fast real charge: " + FishData.SPECIES[kind].id)
		var charge_direction: Vector3 = predator.direction
		game.player.position.x += 5
		game._update_fish(predator,0.01)
		_check(predator.direction.is_equal_approx(charge_direction), "Charge direction remains committed so lateral dodging works: " + FishData.SPECIES[kind].id)
		game.player.position = predator.node.position+Vector3(0.2,0,0)
		game._update_fish(predator,0.01)
		var damage: float = 12.0 if kind == 7 else 18.0
		_check(game.oxygen == 100-damage and predator.state == "recover" and predator.attack_cooldown > 0, "Predator contact damages oxygen once then recovers: " + FishData.SPECIES[kind].id)
		var oxygen_before: float = game.oxygen
		game.take_hunt_damage(damage,false,"Duplicate contact")
		_check(game.oxygen == oxygen_before, "Hurt cooldown prevents repeated contact damage: " + FishData.SPECIES[kind].id)
	_disable_fish()
	game.player.position = Vector3(200,-8,200)
	game.oxygen = 100
	game.hurt_cooldown = 0
	game.poison_timer = 0
	var lionfish := _fixture(5,game.player.position+Vector3(0,0,-1.5))
	game._update_fish(lionfish,0.01)
	_check(game.oxygen == 94 and game.poison_timer > 5.9, "Lionfish contact applies immediate damage and a six-second poison effect")
	lionfish.alive = false
	var poisoned_start: float = game.oxygen
	game._update_dive(1.0)
	_check(absf((poisoned_start-game.oxygen)-2.22) < 0.02 and absf(game.poison_timer-5.0) < 0.02, "Poison adds 1.5 oxygen drain per second on top of normal shallow breathing")
	game.poison_timer = 0.1
	game._update_dive(0.2)
	_check(game.poison_timer == 0, "Poison timer expires instead of draining forever")
func _test_obstruction() -> void:
	_disable_fish()
	game.player.position = Vector3(200,-8,200)
	game.oxygen = 100
	game.poison_timer = 0
	game.hurt_cooldown = 0
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10,10,0.3)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(200,-8,199.25)
	game.add_child(wall)
	await physics_frame
	var shark := _fixture(8,Vector3(200,-8,192))
	_aim_at(shark)
	game.shoot()
	_check(game.target_fish().is_empty() and shark.hp == 8, "Solid geometry blocks actual harpoon acquisition and damage")
	game._update_fish(shark,0.1)
	_check(shark.state == "patrol" and game.oxygen == 100, "A predator cannot see or initiate an attack through a solid wall")
	shark.state = "charge"
	shark.timer = 2.0
	shark.direction = Vector3.BACK
	game._update_fish(shark,1.0)
	_check(shark.state == "recover" and shark.node.position.z < 199.1 and game.oxygen == 100, "Predator swept movement stops a long charge at solid geometry")
	shark.alive = false
	var lionfish := _fixture(5,Vector3(200,-8,198.5))
	game._update_fish(lionfish,0.01)
	_check(game.oxygen == 100 and game.poison_timer == 0, "Nearby venomous fish cannot poison the diver through a solid wall")
	wall.free()
	await physics_frame
	_disable_fish()
	shark = _fixture(8,Vector3(200,-8,180))
	game._hit_fish(shark)
	game._update_fish(shark,0.1)
	_check(shark.state == "windup" and shark.hp == 7, "A surviving predator reacts to a harpoon hit beyond its normal detection range")

func _test_hunting_pause() -> void:
	_disable_fish()
	game.player.position = Vector3(200,-8,200)
	var shark := _fixture(8,game.player.position+Vector3(0,0,-8))
	game._update_fish(shark,0.1)
	game.poison_timer = 4.0
	game.hurt_cooldown = 1.0
	var snapshot: Array = [shark.state,shark.timer,shark.node.transform,shark.attack_cooldown,game.poison_timer,game.oxygen,game.hurt_cooldown,game.hunt_warning_timer,game.clock]
	game.toggle_pause()
	game._physics_process(5.0)
	_check(snapshot == [shark.state,shark.timer,shark.node.transform,shark.attack_cooldown,game.poison_timer,game.oxygen,game.hurt_cooldown,game.hunt_warning_timer,game.clock], "Pause freezes predator windup, pose, poison, damage cooldown, warning and world clock together")
	game.toggle_pause()
	game.finish_dive(false)
	game.start_dive(false, false)
	_check(game.poison_timer == 0 and game.hurt_cooldown == 0 and game.hunt_warning_timer == 0, "Starting a new dive clears poison and hostile warning state")
	game.finish_dive(false)
