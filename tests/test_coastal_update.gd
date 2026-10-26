extends SceneTree
## Actual scene regression and optional captures, with no player save access.
const Cuisine = preload("res://scripts/cuisine.gd")
const Hook = preload("res://scripts/harpoon.gd")
const Feedback = preload("res://scripts/customer_feedback.gd")
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass
var game: Node
var checks := 0
var failures := 0
var captures := false

func _init() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+description)

func capture(label: String) -> void:
	if not captures:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/"+label+".png") == OK,"Capture "+label)

func _run() -> void:
	captures = "--capture-visuals" in OS.get_cmdline_user_args()
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	await process_frame
	await test_projectiles()
	await test_cooking()
	await test_furniture_and_coast()
	game.free()
	await process_frame
	print("%s: Tide Diver coastal update (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func reset_shots() -> void:
	game._clear_projectiles()
	game._update_effects(2)
	game.cargo.clear()
	game.shot_cooldown = 0
	game.player.position = Vector3(200,-8,200)
	game.yaw = 0
	game.pitch = -0.12
	for fish in game.fish:
		fish.alive = false
		fish.node.visible = false

func target(offset: Vector3) -> Dictionary:
	for fish in game.fish:
		if fish.kind == 0 and not fish.alive:
			fish.alive = true
			fish.hp = 1
			fish.armor = false
			fish.node.visible = true
			fish.node.position = game.player.position+offset
			fish.previous_position = fish.node.position
			fish.node.rotation = Vector3.ZERO
			fish.node.scale = Vector3.ONE
			return fish
	return {}

func aim(fish: Dictionary) -> void:
	game.camera.position = game.player.position+Vector3(0,0,7.5)
	game.camera.look_at(fish.node.position)

func fly() -> void:
	for frame in range(60):
		game._update_projectiles(1.0/60.0)

func test_projectiles() -> void:
	game.start_dive(false, false)
	reset_shots()
	var fish := target(Vector3(0,0,-12))
	aim(fish)
	game.shoot()
	check(fish.alive and game.cargo.is_empty() and game.projectiles.size() == 1,"Firing creates one visible hook without instant damage")
	game.shoot()
	check(game.projectiles.size() == 1,"Cooldown prevents another launch")
	var shot: Dictionary = game.projectiles[0]
	var start: Vector3 = shot.node.position
	var initial_velocity: Vector3 = shot.velocity
	game._update_projectiles(0.1)
	check(shot.node.position.distance_to(start) > 2 and fish.alive,"Hook travels through water before reaching fish")
	check(shot.velocity.y < initial_velocity.y and shot.points.size() == 2,"Ballistic fall and visible trail advance")
	var paused_position: Vector3 = shot.node.position
	game.toggle_pause()
	game._update_projectiles(1)
	check(shot.node.position == paused_position and fish.alive,"Pause freezes hook and collisions")
	game.toggle_pause()
	fly()
	check(not fish.alive and game.cargo.size() == 1 and game.projectiles.is_empty(),"Physical impact captures once and removes hook")
	fly()
	check(game.cargo.size() == 1,"Consumed hook cannot pay twice")
	reset_shots()
	fish = target(Vector3(0,0,-12))
	aim(fish)
	game.shoot()
	fish.node.position.x += 4
	fish.previous_position = fish.node.position
	fly()
	check(fish.alive and game.cargo.is_empty(),"Fish that dodges after launch is not hit by homing or hitscan")
	check(game.projectiles.is_empty(),"Missed shot expires at finite range")
	reset_shots()
	var nearer := target(Vector3(0,0,-7))
	var farther := target(Vector3(0,0,-12))
	aim(farther)
	game.shoot()
	game._update_projectiles(0.7)
	check(not nearer.alive and farther.alive and game.cargo.size() == 1,"Swept collision hits nearest fish even in a large frame")
	reset_shots()
	fish = target(Vector3(0.58,-0.15,-6))
	fish.previous_position.x -= 2
	fish.node.position.x += 2
	game.projectiles.append(Hook.launch(game,game.player.position+Vector3(0.58,-0.15,-1.5),Vector3.FORWARD))
	game._update_projectiles(0.375)
	check(not fish.alive,"Swept collision accounts for a fish crossing the flight path between frames")
	reset_shots()
	fish = target(Vector3(0,0,-12))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5,5,0.15)
	collider.shape = box
	wall.add_child(collider)
	game.add_child(wall)
	wall.position = game.player.position+Vector3(0,0,-5)
	await physics_frame
	aim(fish)
	game.shoot()
	fly()
	check(fish.alive and game.cargo.is_empty() and game.projectiles.is_empty(),"World geometry blocks flight before the fish")
	wall.position = game.player.position+Vector3(0,0,-0.75)
	await physics_frame
	game.shot_cooldown = 0
	game.shoot()
	check(game.projectiles.is_empty() and fish.alive,"Close wall also blocks the diver-to-muzzle segment")
	wall.free()
	await physics_frame
	reset_shots()
	fish = target(Vector3(0,0,-14))
	game._update_dive(0)
	fish.node.position = game.camera.position-game.camera.global_basis.z*21
	fish.previous_position = fish.node.position
	game.notice_timer = 0
	game.shoot()
	for frame in range(12):
		game._update_projectiles(1.0/60.0)
	check(game.projectiles.size() == 1 and fish.alive,"Hook is still flying before impact in actual over-shoulder view")
	await capture("hook_flight")
	game.camera.position = game.player.position+Vector3(5,1,-4)
	game.camera.look_at(game.player.position+Vector3(0,-1,-7))
	game.hud.visible = false
	await capture("hook_flight_detail")
	game.hud.visible = true
	game.finish_dive(false)
	check(game.projectiles.is_empty(),"Returning to shore clears airborne hooks")
	check(is_inf(Hook.fraction(Vector3(2,0,0),Vector3(3,0,0))),"Segment outside body has no hit")
	check(is_equal_approx(Hook.fraction(Vector3(-2,0,0),Vector3(2,0,0)),0.25),"Segment returns first body boundary")
	check(Hook.fraction(Vector3.ZERO,Vector3.ONE) == 0,"Shot starting inside a fish hits immediately on simulation")

func test_cooking() -> void:
	game.progress.coins = 5000
	game.open_restaurant()
	for upgrade in ["clean","kitchen","tables","sign","decor"]:
		game.renovate_shop(upgrade)
	game.progress.inventory.orange = 8
	game.progress.inventory.blue = 5
	game.progress.inventory.lantern = 3
	game.restaurant_tab = "menu"
	game.change_menu("orange",2)
	game.prepare_dish("orange")
	check(game.preparation.orange.left == 4 and game.progress.inventory.orange == 8,"Fine preparation starts without consuming stock twice")
	game._update_preparation(1)
	game.prepare_dish("orange")
	check(game.preparation.orange.left == 3,"Repeated preparation cannot restart a batch")
	check(game.restaurant_node._chef.state == "cooking","Chef visibly works while preparing")
	game.start_service()
	check(game.state == "restaurant" and not game.progress.service_active,"Opening waits for current preparation")
	game.change_menu("orange",1)
	check(not game.preparation.has("orange"),"Changing batch size invalidates old preparation")
	game.prepare_dish("orange")
	game.change_seasoning("orange")
	check(not game.preparation.has("orange"),"Changing seasoning requires fresh preparation")
	game.change_menu("orange",-1)
	game.menu_seasoning.orange = 0
	game.prepare_dish("orange")
	game._update_preparation(1.8)
	check(game.preparation_label("orange").contains("切配"),"Preparation displays successive kitchen stages")
	game._physics_process(0)
	await capture("coastal_menu")
	game._update_preparation(2.2)
	check(game.preparation.orange.left == 0 and game.restaurant_node._chef.state == "idle","Prepared batch completes and chef returns to idle")
	game.start_service()
	game._update_service(0.3)
	var order: Dictionary = game.orders[0]
	check(order.prepped and order.seasoning == 0 and order.preference == 0 and game.progress.inventory.orange == 6,"Opening reserves exact stock and transfers preparation and taste")
	game.cook_order(order.id)
	game._update_service(1.5)
	check(Cuisine.heat_fraction(order) == 0.5,"Heat timing follows the actual recipe duration")
	game._physics_process(0)
	await capture("coastal_cooking")
	game.tend_order(order.id)
	check(order.heat_result == "perfect" and Cuisine.quality(order) == 3,"Timed flip in green region earns two quality points")
	game.tend_order(order.id)
	check(Cuisine.quality(order) == 3,"Repeated flip cannot stack quality")
	game._update_service(1.6)
	check(order.state == "ready" and is_equal_approx(order.ready_age,0.1),"Completion accounts for elapsed hot time within frame")
	game.tend_order(order.id)
	check(order.plated and Cuisine.quality(order) == 4 and Cuisine.bonus_percent(order) == 25,"Prep, heat, plating and matched taste earn maximum bonus")
	check(game.restaurant_node._ready_plates[order.id].has_meta("garnished"),"Plating adds actual lemon and herb presentation")
	check(game.order_price(order) == 56,"Displayed payment includes 42 base, 4 decor and 10 quality")
	check(Feedback.outcome(order).text.contains("火候"),"Customer responds to actual cooking quality")
	var before: int = game.progress.coins
	game.serve_order(order.id)
	check(game.progress.coins == before+56 and game.culinary_results.bonus == 10,"Serving pays the displayed quality bonus exactly")
	game.serve_order(order.id)
	check(game.progress.coins == before+56,"Repeated serve never duplicates quality income")
	var second: Dictionary = game.orders[0]
	game.cook_order(second.id)
	game.tend_order(second.id)
	check(second.heat_result == "missed","Early flip misses the heat window")
	game._update_service(1.5)
	game.tend_order(second.id)
	check(second.heat_result == "missed","One attempted flip cannot be retried for a free perfect result")
	game._update_service(1.6)
	game.tend_order(second.id)
	var age: float = second.ready_age
	var patience: float = second.patience
	game.toggle_pause()
	game._physics_process(10)
	game.tend_order(second.id)
	game.serve_order(second.id)
	check(second.ready_age == age and second.patience == patience and game.orders.size() == 1,"Pause freezes temperature, patience and serving")
	game.toggle_pause()
	game._update_service(8.0)
	check(Cuisine.quality(second) == 0 and Cuisine.bonus_percent(second) == 0 and game.order_price(second) == 46,"Cold dish loses all optional quality bonus but keeps base and decor income")
	check(Feedback.outcome(second).mood == "okay","Cold meal produces a lower customer review")
	game.serve_order(second.id)
	game._update_service(0)
	check(game.summary_visible and game.service_summary.culinary == {"excellent":1,"matched":1,"cold":1,"bonus":10},"Bill records excellent meals, preferences, cold dishes and extra revenue")
	await capture("coastal_bill")
	var reload := MemoryProgression.new()
	reload._apply_save_data(game.progress._save_data().duplicate(true))
	check(reload.last_service_result.culinary == game.service_summary.culinary,"Optional culinary summary survives save-data reload")
	var legacy: Dictionary = game.progress._save_data().duplicate(true)
	legacy.last_service_result.erase("culinary")
	reload._apply_save_data(legacy)
	check(reload.last_service_result.earned == 102,"Older bills load without requiring culinary fields")
	var sample := {"prepped":true,"heat_result":"perfect","plated":true,"ready_age":0,"seasoning":0,"preference":1}
	check(Cuisine.bonus_percent(sample) == 20,"Mismatched preference does not award taste bonus")
	sample.heat_result = "missed"
	check(Cuisine.bonus_percent(sample) == 10,"Quality bonus reflects only actually completed actions")
	game.summary_visible = false
	game.preparation.clear()
	game.prepare_dish("blue")
	check(not game.preparation.has("blue"),"Zero-quantity menu cannot create preparation")
	game.change_menu("blue",1)
	game.prepare_dish("blue")
	game.return_to_dock()
	game.start_dive(false, false)
	check(game.preparation.is_empty(),"New diving day clears old preparation")
	game.finish_dive(false)
	game.open_restaurant()

func test_furniture_and_coast() -> void:
	game.enter_layout()
	for item in game.layout_work.furniture_items():
		item.placed = false
	for placement in [["table","premium",-4.5,0.0],["table","comfort",4.5,0.0],["bench","comfort",-6.5,5.5],["parasol","comfort",-6.5,8.0],["coastal","premium",7.5,6.0],["coastal","basic",-3.0,6.0],["plant","premium",8.5,-1.0]]:
		game.buy_layout_furniture(placement[0],placement[1])
		game.place_layout_at(placement[2],placement[3])
		check(game.layout_pending_purchase.is_empty(),"Decorating the actual floor accepts "+placement[0])
	game.layout_selected = -1
	game.hud.restaurant_ui.layout_ui.set_category("parasol")
	game._physics_process(0)
	await capture("coastal_layout")
	game.save_layout()
	game._physics_process(0)
	game.notice_timer = 0
	game.hud.visible = false
	game.camera.position = game.restaurant_node.position+Vector3(24,17,31)
	game.camera.look_at(game.restaurant_node.position+Vector3(0,0,-1))
	await capture("coastal_scene")
	game.hud.visible = true
	check(game.restaurant_node.find_child("LivingCoast",true,false) != null,"Restaurant rebuild includes layered shoreline scenery")
