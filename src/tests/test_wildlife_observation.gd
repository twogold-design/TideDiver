extends SceneTree
## Real visible targets, physical occlusion, capture outcomes and modal input.
const Catalog = preload("res://scripts/wildlife_catalog.gd")
const WATER := Vector3(200,-12,200)

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+description)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	game.start_dive(false,false)
	await physics_frame
	_isolate()
	_test_timing_and_identity()
	await _test_lost_view_and_wall()
	await _test_pause_and_modal_input()
	_test_captures()
	_test_ornamental()
	await _test_discovery_feedback()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver wildlife observation and journal input (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _isolate() -> void:
	game.state = "dive"
	game.entry_active = false
	game.player.position = WATER
	game.player.velocity = Vector3.ZERO
	for item: Dictionary in game.fish:
		item.alive = false
		item.node.visible = false
	game.reef_fish.visible = false
	game.marine_life.visible = false
	game.ray_habitat.visible = false
	game.canyon_shark.visible = false
	game.crevice_habitat.visible = false
	game.wildlife_observation.reset()
	game._clear_projectiles()

func _fish(kind: int, point: Vector3) -> Dictionary:
	var item: Dictionary = game._add_fish(kind,point)
	item.node.position = point
	item.previous_position = point
	item.home = point
	item.node.visible = true
	return item

func _aim(point: Vector3) -> void:
	game.camera.position = game.player.position+Vector3(0,.8,5)
	game.camera.look_at(point,Vector3.UP)
	game.yaw = 0

func _watch(seconds: float) -> void:
	var frames: int = ceili(seconds/.05)
	for frame in range(frames):
		game.wildlife_observation.advance(game,seconds/float(frames))

func _test_timing_and_identity() -> void:
	var a := _fish(0,WATER+Vector3(-2,0,-10))
	var b := _fish(0,WATER+Vector3(2,0,-10))
	_aim(a.node.position)
	_check(game.wildlife_observation.find_target(game).get("key","") == "fish:%d" % a.node.get_instance_id(), "The central view selects a real visible animal rather than only its species")
	_watch(2.9)
	_check(not game.progress.has_discovery("orange") and is_equal_approx(game.wildlife_observation.elapsed,2.9), "Observing the same animal for 2.9 seconds is insufficient")
	_aim(b.node.position)
	_watch(.1)
	_check(game.wildlife_observation.elapsed < .15 and not game.progress.has_discovery("orange"), "Switching to another individual of the same species resets the three-second observation")
	var before: int = game.progress.coins
	_watch(3.0)
	_check(game.progress.has_discovery("orange") and game.progress.discoveries.orange.method == "observed" and game.progress.coins-before == Catalog.entry("orange").reward, "Three seconds on one real visible fish unlocks its record and pays the stated reward")
	var saves: int = game.progress.saves
	_watch(4.0)
	_check(game.progress.coins-before == Catalog.entry("orange").reward and game.progress.saves == saves, "Continuing to observe an unlocked fish never duplicates a reward or save")
	_check(game.cargo.is_empty() and game.progress.inventory_total() == 0, "Observing fish does not create captured inventory")
	_isolate()

func _test_lost_view_and_wall() -> void:
	var item := _fish(1,WATER+Vector3(0,0,-10))
	_aim(item.node.position)
	_watch(2.99)
	game.camera.look_at(game.camera.position+Vector3.RIGHT,Vector3.UP)
	_watch(.02)
	_check(not game.progress.has_discovery("blue") and game.wildlife_observation.target.is_empty() and game.wildlife_observation.elapsed == 0, "Turning away in the final frame cannot unlock a stale cached target and clears observation time")
	item.node.position = WATER+Vector3(0,0,-21)
	_aim(item.node.position)
	_watch(3.2)
	_check(not game.progress.has_discovery("blue") and game.wildlife_observation.target.is_empty(), "An animal beyond twenty metres cannot be observed for the journal")
	item.node.position = WATER+Vector3(0,0,-10)
	_aim(item.node.position)
	item.node.visible = false
	_watch(3.2)
	_check(not game.progress.has_discovery("blue") and game.wildlife_observation.target.is_empty(), "A hidden animal never contributes observation time")
	item.node.visible = true
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = WATER+Vector3(0,0,-5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(5,5,.5)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	wall.add_child(collision)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	_watch(3.2)
	_check(not game.progress.has_discovery("blue") and game.wildlife_observation.target.is_empty(), "A real solid wall blocks observation from the diver and camera")
	wall.queue_free()
	await physics_frame
	await physics_frame
	_watch(1.0)
	_check(game.wildlife_observation.elapsed > .8 and not game.progress.has_discovery("blue"), "Observation starts fresh only after the obstruction is removed")
	_isolate()

func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	Input.parse_input_event(up)
	await process_frame

func _click(point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(up)
	await process_frame

func _test_pause_and_modal_input() -> void:
	var item := _fish(2,WATER+Vector3(0,0,-10))
	_aim(item.node.position)
	_watch(1.0)
	var elapsed: float = game.wildlife_observation.elapsed
	game.state = "paused"
	_watch(6.0)
	_check(game.wildlife_observation.elapsed == elapsed and not game.progress.has_discovery("lantern"), "Pause freezes partial observation without granting discoveries")
	game.state = "dive"
	await _key(KEY_B)
	_check(game.bestiary_open and game.state == "paused" and game.hud.bestiary_ui.visible and game.hud.buttons.is_empty(), "The real B key opens the journal, pauses the dive and removes the underlying HUD controls")
	var air: float = game.oxygen
	game._physics_process(.4)
	_watch(4.0)
	var projectiles: int = game.projectiles.size()
	await _key(KEY_SPACE)
	await _click(Vector2(240,515))
	_check(game.bestiary_open and game.projectiles.size() == projectiles and game.oxygen == air and game.wildlife_observation.elapsed == elapsed, "Journal inputs cannot fire a hook, consume air or advance observation behind the modal")
	await _key(KEY_B)
	_check(not game.bestiary_open and game.state == "dive" and not game.entry_active, "Closing the journal with B resumes the original dive without starting a new entry")
	_watch(2.2)
	_check(game.progress.has_discovery("lantern"), "A paused partial observation can finish after resuming the same target")
	game.state = "dock"
	game.hud.rebuild()
	await _key(KEY_B)
	await _click(Vector2(240,515))
	_check(game.bestiary_open and game.state == "dock" and not game.entry_active, "Clicking the old departure area while the dock journal is open cannot accidentally launch a dive")
	await _key(KEY_ESCAPE)
	_check(not game.bestiary_open and game.state == "dock", "Escape closes the dock journal and retains the dock state")
	game.state = "restaurant"
	game.hud.rebuild()
	await _key(KEY_B)
	_check(game.bestiary_open and game.hud.restaurant_ui.buttons.is_empty(), "Opening the restaurant journal removes the underlying shop controls")
	await _key(KEY_ESCAPE)
	_check(not game.bestiary_open and game.state == "restaurant", "Closing the restaurant journal restores the restaurant")
	_isolate()

func _test_captures() -> void:
	var target := _fish(1,WATER+Vector3(0,0,-10))
	game.progress.spear_level = 3
	game.cargo.clear()
	game.shot_cooldown = 0
	_aim(target.node.position)
	var before: int = game.progress.coins
	game.shoot()
	for frame in range(60):
		game._update_projectiles(.02)
	_check(not target.alive and game.cargo.size() == 1 and game.progress.has_discovery("blue") and game.progress.discoveries.blue.method == "caught", "A real fired harpoon that captures one fish immediately unlocks its catalog record")
	_check(game.progress.coins-before == Catalog.entry("blue").reward, "A successful physical capture pays one discovery reward")
	var second := _fish(1,WATER+Vector3(2,0,-10))
	game._hit_fish(second,99)
	_check(game.progress.coins-before == Catalog.entry("blue").reward and game.cargo.size() == 2, "A second capture of the species adds cargo but does not repeat its discovery reward")
	game.cargo.clear()
	for index in range(game.progress.capacity()):
		game.cargo.append({"id":"orange","name":"橘鳍鱼","weight":1,"value":18,"kind":"fish"})
	var too_large := _fish(6,WATER+Vector3(0,0,-8))
	before = game.progress.coins
	game._hit_fish(too_large,99)
	_check(too_large.alive and too_large.hp == 1 and not game.progress.has_discovery("tuna") and game.progress.coins == before, "A full-bag failed capture cannot unlock a new species or pay a reward")
	game.cargo.clear()
	_isolate()

func _test_ornamental() -> void:
	game.crevice_habitat.visible = true
	var cave: Node3D = game.crevice_habitat.clam_den
	cave.visible = true
	var point: Vector3 = cave.to_global(Vector3(0,.8,-.6))
	game.player.position = cave.to_global(Vector3(0,1.25,-4))
	game.camera.position = cave.to_global(Vector3(0,1.4,-5.5))
	game.camera.look_at(point,Vector3.UP)
	var before: int = game.progress.coins
	var inventory: Dictionary = game.progress.inventory.duplicate(true)
	_check(game.wildlife_observation.find_target(game).get("id","") == "lightning_clam", "The actual ornamental clam inside its cave is an observable target")
	_watch(3.1)
	_check(game.progress.has_discovery("lightning_clam") and game.progress.coins-before == Catalog.entry("lightning_clam").reward, "Three seconds of watching the real clam unlocks its ornamental catalog reward")
	_check(game.progress.inventory == inventory and game.cargo.is_empty(), "Ornamental discovery never creates a captured clam or cargo item")

func _test_discovery_feedback() -> void:
	_isolate()
	game.progress.mark_discoveries_seen()
	game.discovery_notifications.clear()
	game.discovery_notification_timer = 0.0
	game.record_species("reef_clown","observed")
	game.tell("普通采集提示",2.0)
	_check(game.discovery_notifications.size() == 1 and game.discovery_notifications[0].name == Catalog.entry("reef_clown").name and game.discovery_notification_timer == 5.0, "A first discovery retains its independent five-second card after an ordinary tell message")
	game.record_species("tuna","caught")
	_check(game.discovery_notifications.size() == 2 and game.progress.unread_discoveries() == 2, "Distinct discoveries queue in order and each sets one unread record")
	game.record_species("reef_clown","observed")
	game.record_species("tuna","caught")
	_check(game.discovery_notifications.size() == 2 and game.progress.unread_discoveries() == 2, "Duplicate observation or capture does not add notification cards or unread counts")
	game._advance_discovery_notifications(4.9)
	_check(game.discovery_notifications.size() == 2 and game.discovery_notifications[0].name == Catalog.entry("reef_clown").name, "A queued card remains visible until its five-second duration finishes")
	var remaining: float = game.discovery_notification_timer
	game.state = "paused"
	game._advance_discovery_notifications(20.0)
	_check(game.discovery_notifications.size() == 2 and game.discovery_notification_timer == remaining, "Pausing freezes the discovery notification queue and remaining time")
	game.state = "dive"
	game._advance_discovery_notifications(.11)
	_check(game.discovery_notifications.size() == 1 and game.discovery_notifications[0].name == Catalog.entry("tuna").name and game.discovery_notification_timer == 5.0, "The second discovery rotates in after the first and receives a full five seconds")
	game._advance_discovery_notifications(5.0)
	_check(game.discovery_notifications.is_empty() and game.progress.unread_discoveries() == 2 and game.bestiary_button_label().contains("新2"), "Expired cards leave their persistent journal unread indicator")
	game.open_bestiary()
	_check(game.bestiary_open and game.progress.unread_discoveries() == 0 and game.discovery_notifications.is_empty() and game.discovery_notification_timer == 0.0, "Opening the journal marks discoveries read and clears notification state")
	game.close_bestiary()
	_check(game.state == "dive" and game.progress.unread_discoveries() == 0 and not game.bestiary_button_label().contains("●"), "Closing the journal keeps the cleared unread indicator cleared")
	game.record_species("reef_chromis","observed")
	_check(game.progress.unread_discoveries() == 1 and game.bestiary_button_label().contains("新1") and game.bestiary_button_label(true).contains("● 1"), "A later discovery lights the full and compact journal indicators again")
	game.open_bestiary()
	_check(game.discovery_notifications.is_empty() and game.discovery_notification_timer == 0.0 and game.progress.unread_discoveries() == 0, "Opening the journal also dismisses a still-active discovery card")
	game.close_bestiary()
	if DisplayServer.get_name() != "headless":
		await _capture_discovery_feedback()

func _capture_discovery_feedback() -> void:
	root.size = Vector2i(1440,900)
	var output := ProjectSettings.globalize_path("res://../.runtime/bestiary-notifications")
	DirAccess.make_dir_recursive_absolute(output)
	game.state = "dock"
	game.start_dive(false,false)
	game._clear_loot_feedback()
	game._physics_process(0.0)
	game.record_species("reef_butterfly","observed")
	game.record_species("reef_tang","observed")
	game.tell("拾取珍珠 · +1",2.0)
	game._apply_underwater_lighting(maxf(0.0,-game.player.position.y))
	game.hud.rebuild()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+"/dive-notification.png") == OK, "Capture the real dive discovery card and queued-message footer")
	game.finish_dive(false)
	_check(game.state == "dock" and game.progress.unread_discoveries() == 2, "Returning from the dive retains unread discoveries on the dock")
	game.harvest_result_visible = false
	game._physics_process(0.0)
	game.hud.rebuild()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+"/dock-unread.png") == OK, "Capture the real dock journal button with its unread indicator")
