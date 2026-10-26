extends SceneTree
## Exercises the real main scene and UI with an in-memory save before _ready.
class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1
var game: Node
var progress: MemoryProgression
var checks: int = 0
var failures: int = 0
func _init() -> void:
	call_deferred("_run")
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _button(fragment: String) -> Button:
	for button in game.hud.restaurant_ui.buttons:
		if button.text.contains(fragment):
			return button
	return null
func _button_disabled(fragment: String) -> bool:
	var button := _button(fragment)
	return button != null and button.disabled
func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		printerr("FAIL: main scene did not load")
		quit(1)
		return
	game = scene.instantiate()
	progress = MemoryProgression.new()
	progress.persistence_enabled = false
	game.progress = progress
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.smoke_mode = true
	await physics_frame
	await process_frame
	_test_fund_and_restore()
	_test_first_service()
	_test_next_day_and_early_close()
	_test_extended_recipe_timing_and_tips()
	_test_timeout_stages()
	_test_four_seats_and_guest_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver restaurant flow (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _test_fund_and_restore() -> void:
	_check(progress.coins == 0 and progress.inventory_total() == 0, "Real game starts with zero funds and stock")
	game.open_restaurant()
	_check(game.state == "restaurant" and game.restaurant_node.visible and not game.environment.fog_enabled, "Restaurant entrance switches the real world view")
	_check(_button_disabled("开门营业") and _button_disabled("40 G") and _button_disabled("卖 1 件"), "Empty old shop disables opening, construction and selling")
	game.start_service()
	_check(game.state == "restaurant", "Unrestored restaurant cannot start service")
	game.return_to_dock()
	game.start_dive()
	game.cargo = [{"id":"chest","weight":3},{"id":"chest","weight":3},{"id":"pearl","weight":1}]
	for i in range(5):
		game.cargo.append({"id":"orange","weight":1,"kind":"fish"})
	_check(game.weight() == 12, "Startup harvest respects initial diving capacity")
	game.finish_dive(false)
	_check(progress.day == 2 and progress.coins == 0 and progress.inventory.orange == 5 and progress.inventory.chest == 2 and progress.inventory.pearl == 1, "Real dive return puts all harvest into warehouse")
	game.open_restaurant()
	game.sell_valuables()
	game.sell_goods("orange", 1)
	_check(progress.coins == 226 and progress.inventory.orange == 4 and progress.inventory.chest == 0, "Selling valuables and one fish funds the shop")
	game.renovate_shop("kitchen")
	_check(not progress.renovation.kitchen and progress.coins == 226, "Main renovation action respects prerequisites")
	game.renovate_shop("clean")
	game.renovate_shop("kitchen")
	game.renovate_shop("tables")
	_check(progress.can_open() and progress.coins == 16 and game.restaurant_node._renovation.tables, "Minimum renovation updates data and actual 3D shop")
	_check(_button_disabled("开门营业"), "Opening stays disabled until menu is prepared")
	game.restaurant_tab = "menu"
	game.change_menu("orange", 999)
	_check(game.menu_plan.orange == 4, "Menu increments clamp to real stock")
	game.sell_goods("orange", 1)
	_check(game.menu_plan.orange == 3 and progress.inventory.orange == 3, "Selling planned ingredients automatically clamps the menu")
	game.change_menu("orange", -999)
	game.change_menu("orange", 2)
	_check(game.menu_plan.orange == 2 and not _button_disabled("开门营业"), "A valid menu enables the opening button")
func _test_first_service() -> void:
	game.start_service()
	_check(game.state == "service" and progress.inventory.orange == 1 and game.service_remaining() == 2, "Starting real service reserves menu stock")
	game.sell_goods("orange",1)
	game.renovate_shop("sign")
	game.change_menu("orange",1)
	_check(progress.inventory.orange == 1 and not progress.renovation.sign and game.menu_plan.orange == 2, "Management actions are blocked during service")
	game._update_service(0.3)
	_check(game.orders.size() == 1 and game.orders[0].state == "waiting" and _button("开始制作") != null, "Customer arrival creates an actionable order")
	game._update_service(2.1)
	_check(game.orders.size() == 2 and game.restaurant_node._customers.size() == 2, "Two seats display two actual 3D guests")
	var order: Dictionary = game.orders[0]
	var first_id: int = order.id
	var money_before: int = progress.coins
	game.serve_order(first_id)
	_check(progress.coins == money_before and order.state == "waiting", "Uncooked dishes cannot be served")
	game.cook_order(first_id)
	order.cook_left -= 0.1
	game.cook_order(first_id)
	_check(order.state == "cooking" and _button("翻面") != null and order.cook_left < order.cook_total, "Cooking exposes heat action and cannot be restarted")
	game.serve_order(first_id)
	_check(progress.coins == money_before, "Cooking dishes cannot be served early")
	game.toggle_pause()
	var patience_before: float = order.patience
	var cooking_before: float = order.cook_left
	var arrival_before: float = game.service_spawn_time
	game._physics_process(15.0)
	game.cook_order(game.orders[1].id)
	game.serve_order(first_id)
	_check(game.state == "service_paused" and order.patience == patience_before and order.cook_left == cooking_before and game.service_spawn_time == arrival_before, "Pause freezes patience, cooking and arrivals")
	_check(game.orders[1].state == "waiting" and progress.coins == money_before and _button("继续营业") != null, "Paused input cannot cook or serve and exposes resume control")
	game.toggle_pause()
	game._update_service(3.01)
	_check(order.state == "ready" and _button("上菜") != null and not _button("上菜").disabled, "Cooking completion immediately enables serving button")
	game.serve_order(first_id)
	_check(progress.coins == money_before + 42 and progress.total_served == 1 and game.orders.size() == 1, "Serving earns income and removes the fulfilled guest")
	game.serve_order(first_id)
	_check(progress.coins == money_before + 42, "Repeated serving cannot pay twice")
	game._update_service(25.0)
	_check(game.state == "restaurant" and game.summary_visible and game.orders.is_empty(), "Last customer timeout automatically closes depleted menu")
	_check(game.service_summary.earned == 42 and game.service_summary.served == 1 and game.service_summary.lost == 1 and progress.inventory.orange == 1, "Bill correctly distinguishes served, lost and remaining warehouse stock")
	_check(_button("收好账单") != null and game.hud.restaurant_ui.buttons.size() == 1, "Bill exposes a clear close action")
	_button("收好账单").pressed.emit()
	_check(not game.summary_visible and _button_disabled("开门营业"), "Closing bill restores management with same-day opening disabled")
	game.start_service()
	_check(game.state == "restaurant" and progress.restaurant_runs == 1, "Real UI cannot reopen service on the same day")
func _test_next_day_and_early_close() -> void:
	game.return_to_dock()
	game.start_dive()
	game.cargo = [{"id":"orange","weight":1},{"id":"orange","weight":1},{"id":"orange","weight":1}]
	game.finish_dive(false)
	game.open_restaurant()
	game.change_menu("orange", -999)
	game.change_menu("orange", 4)
	game.start_service()
	_check(progress.day == 3 and game.state == "service" and progress.last_service_day == 3, "Returning from another dive enables next service")
	game._update_service(0.3)
	_check(game.orders.size() == 1 and game.service_remaining() == 3, "Second service has one allocated and three unassigned portions")
	game.toggle_pause()
	game.finish_service()
	_check(game.state == "restaurant" and game.service_summary.lost == 1 and game.service_summary.returned == 3 and progress.inventory.orange == 3, "Early close from pause loses pending order and returns only unassigned portions")
	var money_before: int = progress.coins
	game.finish_service()
	_check(progress.restaurant_runs == 2 and progress.total_lost == 2 and progress.inventory.orange == 3 and progress.coins == money_before, "Repeated close cannot duplicate refunds or cumulative records")
	_check(progress.saves > 0, "Entire flow exercises persistence hooks without touching player files")

func _prepare_full_shop(stock: Dictionary) -> void:
	progress = MemoryProgression.new()
	progress.persistence_enabled = false
	game.progress = progress
	for id in progress.RENOVATIONS:
		progress.renovation[id] = true
	for id in stock:
		progress.inventory[id] = stock[id]
	game.state = "dock"
	game.summary_visible = false
	game.service_summary.clear()
	game.menu_plan = {"orange":0,"blue":0,"lantern":0}
	game.open_restaurant()
	for id in stock:
		game.change_menu(id, stock[id])
	game.start_service()
	game.service_spawn_time = 999.0

func _test_extended_recipe_timing_and_tips() -> void:
	_prepare_full_shop({"orange":1,"blue":1,"lantern":1})
	for i in range(3):
		game._spawn_customer()
	var orange: Dictionary = game.orders[0]
	var blue: Dictionary = game.orders[1]
	var lantern: Dictionary = game.orders[2]
	for order in game.orders:
		game.cook_order(order.id)
	_check(orange.cook_left == 3.0 and blue.cook_left == 4.0 and lantern.cook_left == 5.0, "Real orders initialize exact 3/4/5-second recipe clocks")
	game._update_service(2.99)
	_check(orange.state == "cooking" and blue.state == "cooking" and lantern.state == "cooking", "No recipe finishes before its cooking time")
	game._update_service(0.02)
	_check(orange.state == "ready" and blue.state == "cooking" and lantern.state == "cooking", "Orange recipe finishes after 3 seconds while others cook")
	game._update_service(0.98)
	_check(blue.state == "cooking", "Blue recipe remains cooking just before 4 seconds")
	game._update_service(0.02)
	_check(blue.state == "ready" and lantern.state == "cooking", "Blue recipe finishes after 4 seconds while lantern cooks")
	game._update_service(0.98)
	_check(lantern.state == "cooking", "Lantern recipe remains cooking just before 5 seconds")
	game._update_service(0.02)
	_check(lantern.state == "ready", "Lantern recipe finishes after 5 seconds")
	game.serve_order(orange.id)
	_check(progress.coins == 46, "Actual orange serving earns 42 plus 4 tip")
	game.serve_order(blue.id)
	_check(progress.coins == 125, "Actual blue serving earns 72 plus 7 tip")
	game.serve_order(lantern.id)
	_check(progress.coins == 257 and progress.restaurant_income == 257, "Actual lantern serving earns 120 plus 12 tip")
	game._update_service(0.0)
	_check(game.state == "restaurant" and game.service_summary.served == 3, "Three-recipe sold-out service closes automatically")

func _test_timeout_stages() -> void:
	_prepare_full_shop({"orange":1,"lantern":1})
	game._spawn_customer()
	game._spawn_customer()
	var orange: Dictionary = game.orders[0]
	var lantern: Dictionary = game.orders[1]
	game.cook_order(orange.id)
	game.cook_order(lantern.id)
	game._update_service(3.01)
	_check(orange.state == "ready" and lantern.state == "cooking", "Timeout fixture contains ready and still-cooking orders")
	orange.patience = 0.1
	lantern.patience = 0.1
	game._update_service(0.2)
	_check(game.orders.is_empty() and game.state == "restaurant" and progress.total_lost == 2, "Both ready-to-serve and cooking orders can time out")
	_check(progress.coins == 0 and progress.restaurant_income == 0 and progress.inventory_total() == 0 and game.service_summary.returned == 0, "Timed-out prepared and cooking dishes yield no income or refunds")

func _test_four_seats_and_guest_target() -> void:
	_prepare_full_shop({"orange":10})
	for i in range(5):
		game._spawn_customer()
	_check(game.orders.size() == 4 and game.restaurant_node._customers.size() == 4 and game.service_arrived == 4, "Expanded shop creates exactly four visible guests and rejects a fifth concurrent guest")
	for round_index in range(2):
		if round_index > 0:
			for i in range(4):
				game._spawn_customer()
		for order in game.orders:
			game.cook_order(order.id)
		game._update_service(3.01)
		for order in game.orders.duplicate():
			game.serve_order(order.id)
		game._update_service(0.0)
		if round_index == 0:
			_check(game.state == "service" and game.service_arrived == 4, "Service continues until its target after the first seating")
	_check(game.state == "restaurant" and game.service_arrived == 8 and game.service_summary.served == 8, "Eight-customer target automatically closes service even with menu portions left")
	_check(game.service_summary.returned == 2 and progress.inventory.orange == 2 and progress.coins == 368, "Target closure returns two unallocated portions and pays eight tipped dishes")
