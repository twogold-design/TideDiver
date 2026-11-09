extends SceneTree
## Restaurant debug spending uses real purchases without minting refundable money.
const P = preload("res://scripts/progression.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+message)

func _run() -> void:
	_test_economy()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var progress := MemoryProgression.new()
	progress.persistence_enabled = false
	game.progress = progress
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	game.open_restaurant()
	var button: Button
	var book: Button
	for control: Button in game.hud.restaurant_ui.buttons:
		if control.text.begins_with("GM 无限金币"):
			button = control
		if control.text.begins_with("图鉴 · B"):
			book = control
	check(button != null and not button.disabled and book != null,"The restaurant exposes an enabled GM switch and a separate encyclopedia entry")
	if button != null:
		button.pressed.emit()
	check(progress.gm_infinite_coins and progress.coins == 0 and progress.saves == 0,"Actual GM button enables free spending without minting coins or saving the debug flag")
	game.renovate_shop("clean")
	game.renovate_shop("kitchen")
	game.renovate_shop("tables")
	check(progress.renovation.clean and progress.renovation.kitchen and progress.renovation.tables and progress.coins == 0,"Real renovation callbacks complete eligible upgrades with zero coins")
	game.enter_layout()
	check(game.layout_work.gm_infinite_coins and game.layout_work != progress,"The isolated layout draft inherits infinite spending")
	var buy_button: Button
	for control: Node in game.hud.restaurant_ui.layout_ui.controls:
		if control is Button and control.text == "GM 免费选购":
			buy_button = control
	check(buy_button != null and not buy_button.disabled,"The zero-coin shop enables its free furniture purchase button")
	game.buy_layout_furniture("lamp")
	check(game.layout_selected >= 100 and game.layout_pending_purchase.cost == 0 and game.layout_work.coins == 0,"Pending free furniture reserves zero real coins")
	game.cancel_layout_placement()
	check(game.layout_pending_purchase.is_empty() and game.layout_work.coins == 0,"Cancelling a free purchase cannot issue a fictitious refund")
	game.buy_layout_furniture("lamp")
	var uid: int = game.layout_selected
	check(game.place_layout_at(5.5,4.5),"Free furniture can be physically placed through the real layout flow")
	game.save_layout()
	check(progress.coins == 0 and progress.furniture_by_uid(uid).get("gm_free",false) and progress.furniture_by_uid(uid).placed,"Saving commits free ownership while preserving the actual balance")
	game.enter_layout()
	game.select_furniture(uid)
	game.recycle_selected_furniture()
	check(game.layout_work.furniture_by_uid(uid).is_empty() and game.layout_work.coins == 0,"Free furniture can be recycled without generating coins")
	game.undo_layout()
	check(game.layout_work.furniture_by_uid(uid).get("gm_free",false) and game.layout_work.coins == 0,"Undo restores zero-refund ownership and no artificial money")
	game.select_furniture(uid)
	game.recycle_selected_furniture()
	game.cancel_layout()
	check(not progress.furniture_by_uid(uid).is_empty() and progress.coins == 0,"Cancelling layout restores the free item and the original balance")
	game.toggle_gm_infinite_coins()
	check(not progress.gm_infinite_coins and progress.coins == 0,"Disabling GM restores the unchanged actual balance")
	game.enter_layout()
	game.buy_layout_furniture("lamp")
	check(game.layout_pending_purchase.is_empty(),"Normal zero-coin spending is rejected after disabling the switch")
	game.cancel_layout()
	game.toggle_gm_infinite_coins()
	progress.inventory.orange = 1
	game.sell_goods("orange",1)
	check(progress.coins == 18 and progress.inventory.orange == 0,"Real restaurant income still accumulates while GM is active")
	game.free()
	await process_frame
	print("%s: Tide Diver restaurant GM coins (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _test_economy() -> void:
	var p := P.new()
	p.persistence_enabled = false
	check(not p.gm_infinite_coins and not p.renovate("clean"),"Fresh profiles default to ordinary affordability rules")
	p.gm_infinite_coins = true
	check(not p.can_afford(-1) and not p.spend_coins(-1),"Negative prices cannot add money under GM")
	check(not p.renovate("kitchen"),"Infinite coins preserve renovation prerequisites")
	check(p.renovate("clean") and p.coins == 0,"GM renovation bypasses only the coin requirement")
	p.renovate("tables")
	check(p.furniture_by_uid(1).get("gm_free",false) and p.furniture_refund(1) == 0,"Gifts from free renovations cannot be exchanged for real coins")
	var uid: int = p.buy_furniture("plant")
	check(uid >= 100 and p.furniture_refund(uid) == 0 and p.coins == 0,"GM furniture has no refundable acquisition cost")
	var saved: Dictionary = p._save_data().duplicate(true)
	check(not saved.has("gm_infinite_coins"),"Debug spending flag is absent from saved progress")
	saved["gm_infinite_coins"] = true
	var loaded := P.new()
	loaded.persistence_enabled = false
	loaded._apply_save_data(saved)
	check(not loaded.gm_infinite_coins and loaded.furniture_refund(uid) == 0,"Reload disables GM while preserving free-item refund restrictions")
	check(loaded.recycle_furniture(uid) == 0 and loaded.furniture_by_uid(uid).is_empty() and loaded.coins == 0,"Reloaded free items can be removed without a refund exploit")
	loaded.coins = 100
	var paid: int = loaded.buy_furniture("plant")
	check(paid >= 100 and loaded.coins == 75 and loaded.furniture_refund(paid) == 13,"Paid purchases and ordinary half-price refunds keep their established values")
	loaded.gm_infinite_coins = true
	check(loaded.recycle_furniture(paid) == 13 and loaded.coins == 88,"Enabling GM does not erase a previously paid item's valid refund")
	p.service_active = true
	check(p.buy_furniture("lamp") == -1 and not p.renovate("kitchen"),"Infinite coins preserve service-time shopping restrictions")
