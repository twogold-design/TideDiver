extends SceneTree
## New-game reset tests. Only tests/temp/new_game.json is ever persisted.
const P = preload("res://scripts/progression.gd")
const TEST_PATH := "res://tests/temp/new_game.json"
var checks: int = 0
var failures: int = 0
var game: Node
func _init() -> void:
	call_deferred("_run")
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _seed(p: RefCounted, active: bool = true) -> void:
	p.coins = 12345
	p.day = 19
	p.tank_level = 3
	p.bag_level = 2
	p.spear_level = 1
	p.total_fish = 87
	p.best_depth = 49.5
	p.inventory = {"orange":9,"blue":7,"lantern":5,"pearl":3,"chest":2}
	for id in p.RENOVATIONS:
		p.renovation[id] = true
	p.furniture_items()
	p.buy_furniture("lamp","premium")
	p.floor_style = 2
	p.wall_style = 1
	p.restaurant_runs = 11
	p.total_served = 44
	p.total_lost = 7
	p.restaurant_income = 4321
	p.last_service_day = 19
	p.service_active = active
	p.service_stock = {"orange":2,"blue":1,"lantern":0}
	var pending: Array[String] = ["orange"]
	p.service_pending = pending
	p.service_stats = {"earned":42,"served":1,"lost":1}
	p.last_service_result = {"earned":321,"served":4,"lost":1,"returned":2}
	p.recovery_notice = "old recovery notice"
func _fresh_checks(p: RefCounted, label: String) -> void:
	_check(p.coins == 0 and p.day == 1 and p.tank_level == 0 and p.bag_level == 0 and p.spear_level == 0, label + ": coins, day and equipment reset")
	_check(p.inventory_total() == 0 and p.total_fish == 0 and p.best_depth == 0.0, label + ": inventory and diving records reset")
	var clean_flags: bool = true
	for flag in p.renovation.values():
		clean_flags = clean_flags and not flag
	_check(clean_flags and p.furniture_items().is_empty() and p.floor_style == 0 and p.wall_style == 0 and p.next_furniture_uid == 100, label + ": old shop, furniture and styles reset")
	_check(p.restaurant_runs == 0 and p.total_served == 0 and p.total_lost == 0 and p.restaurant_income == 0 and p.last_service_day == 0, label + ": restaurant records reset")
	var remaining: int = 0
	for amount in p.service_stock.values():
		remaining += int(amount)
	_check(not p.service_active and remaining == 0 and p.service_pending.is_empty() and p.service_stats.earned == 0 and p.service_stats.served == 0 and p.service_stats.lost == 0 and p.last_service_result.is_empty(), label + ": incomplete service cannot survive reset")
func _clear_fixture() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
func _test_disk_reset() -> void:
	_clear_fixture()
	var p = P.new()
	p.persistence_enabled = false
	_seed(p)
	p.save_path = TEST_PATH
	p.persistence_enabled = true
	p.save_game()
	p.coins += 1
	p.save_game()
	_check(FileAccess.file_exists(TEST_PATH) and FileAccess.file_exists(TEST_PATH + ".bak"), "Rich old-run fixture and backup exist only under tests/temp")
	_check(p.reset_game(), "Persistent new-game reset reports success")
	_fresh_checks(p, "Immediately after reset")
	_check(p.save_path == TEST_PATH and p.persistence_enabled, "Reset preserves isolated save destination and persistence mode")
	var primary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH + ".bak"))
	_check(primary.day == 1 and primary.coins == 0 and backup.day == 1 and backup.coins == 0, "Both primary and backup contain the fresh run")
	var loaded = P.new()
	loaded.save_path = TEST_PATH
	loaded.load_game()
	_fresh_checks(loaded, "Normal reload")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{broken primary after new-game reset")
	file.close()
	var recovered = P.new()
	recovered.save_path = TEST_PATH
	recovered.load_game()
	_fresh_checks(recovered, "Backup recovery after corrupt primary")
	_check(not recovered.recovery_notice.is_empty(), "Backup recovery provides a notice without resurrecting the old run")
	_clear_fixture()
func _test_failure_and_memory_reset() -> void:
	var p = P.new()
	p.persistence_enabled = false
	_seed(p)
	p.save_path = "res://../new_game_forbidden.json"
	p.persistence_enabled = true
	var before: Dictionary = p._save_data().duplicate(true)
	_check(not p.reset_game() and p._save_data() == before, "Invalid persistence destination leaves old in-memory progress completely intact")
	p.persistence_enabled = false
	_check(p.reset_game(), "Disabled persistence resets memory even with an unusable path")
	_fresh_checks(p, "Memory-only reset")
	_check(not p.persistence_enabled and p.save_path == "res://../new_game_forbidden.json", "Memory reset does not enable persistence or change its destination")
func _hud_button(fragment: String) -> Button:
	for button in game.hud.buttons:
		if button.text.contains(fragment):
			return button
	return null
func _test_scene_confirmation() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	var isolated = P.new()
	isolated.persistence_enabled = false
	isolated.save_path = TEST_PATH
	_seed(isolated,false)
	game.progress = isolated
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.smoke_mode = true
	await physics_frame
	await process_frame
	var before: Dictionary = game.progress._save_data().duplicate(true)
	_check(_hud_button("重新开始") != null and not game.new_game_confirmation, "Dock exposes restart without opening confirmation automatically")
	game.confirm_new_game()
	_check(game.progress._save_data() == before, "Unsolicited confirmation cannot reset progress")
	game.request_new_game()
	_check(game.new_game_confirmation and game.progress._save_data() == before, "Request opens a confirmation without mutating saved progress")
	_check(_hud_button("取消") != null and game.hud.buttons[0].text.contains("取消"), "Cancellation is present and receives first visual/action priority")
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	_check(game.new_game_confirmation and game.progress._save_data() == before, "Enter does not silently choose destructive confirmation")
	game.cancel_new_game()
	_check(not game.new_game_confirmation and game.state == "dock" and game.progress._save_data() == before, "Cancelling from dock preserves all progress")
	game.open_restaurant()
	game.request_new_game()
	_check(not game.new_game_confirmation, "Restaurant management cannot open restart confirmation")
	game.return_to_dock()
	game.start_dive(false, false)
	game.request_new_game()
	_check(not game.new_game_confirmation and game.state == "dive", "Active diving cannot open restart confirmation")
	game.toggle_pause()
	_check(_hud_button("重新开始") != null, "Paused dive also exposes restart")
	game.request_new_game()
	game.cancel_new_game()
	_check(game.state == "paused" and game.progress._save_data() == before, "Cancelling a paused restart preserves both pause and progress")
	game.progress.persistence_enabled = true
	game.progress.save_path = "res://../new_game_forbidden.json"
	game.request_new_game()
	game.confirm_new_game()
	_check(game.state == "paused" and game.new_game_confirmation and game.progress._save_data() == before, "Scene-level save failure preserves old run and keeps confirmation open")
	_check(not game.new_game_error.is_empty() and _hud_button("取消") != null, "Save failure keeps a visible modal error and safe cancellation action")
	game.cancel_new_game()
	game.progress.persistence_enabled = false
	game.progress.save_path = TEST_PATH
	game.cargo = [{"id":"chest","weight":3,"value":90}]
	game.last_result = {"count":1,"earned":90,"day":18}
	game.depth_record = 35.0
	game.oxygen = 1.0
	game.shot_cooldown = 4.0
	game.hurt_cooldown = 5.0
	game.entry_active = true
	game.catch_timer = 2.4
	game.hit_timer = 0.4
	game.menu_plan = {"orange":5,"blue":4,"lantern":3}
	game.service_summary = {"earned":123,"served":2,"lost":1,"returned":0}
	game.summary_visible = true
	game.layout_selected = 100
	game.layout_history = [{"coins":99}]
	game.request_new_game()
	game.confirm_new_game()
	_check(game.state == "dock" and not game.new_game_confirmation, "Confirmed paused restart returns to clean dock")
	_fresh_checks(game.progress, "Real scene reset")
	_check(game.cargo.is_empty() and game.last_result.is_empty() and game.depth_record == 0.0 and game.oxygen == 100.0, "Scene clears dive cargo, bill, depth and oxygen")
	_check(not game.entry_active and game.catch_timer == 0.0 and game.hit_timer == 0.0, "Scene clears active water entry and catch feedback when restarting")
	_check(game.menu_total() == 0 and game.orders.is_empty() and game.service_summary.is_empty() and not game.summary_visible, "Scene clears menu, active orders and restaurant bill")
	_check(not game.layout_mode and game.layout_history.is_empty() and game.layout_selected == -1 and game.shot_cooldown == 0.0 and game.hurt_cooldown == 0.0, "Scene clears layout drafts and combat cooldowns")
	game.open_restaurant()
	_check(game.state == "restaurant" and not game.progress.can_open() and game.progress.furniture_items().is_empty(), "Restarted restaurant returns to the abandoned shop")
	game.return_to_dock()
	game.start_dive(false, false)
	_check(game.state == "dive" and game.oxygen == 100.0 and game.fish.size() == game.fish_population_count() and game.pickups.size() == 11 + game.Ocean.pickup_points().size(), "Restarted player can immediately begin a fresh playable dive")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
func _run() -> void:
	_test_disk_reset()
	_test_failure_and_memory_reset()
	await _test_scene_confirmation()
	print("%s: Tide Diver new game (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

