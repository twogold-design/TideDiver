extends SceneTree
## Restaurant transactions and real persistence fixtures, confined to tests/temp.
const Progress = preload("res://scripts/progression.gd")
const TEST_PATH := "res://tests/temp/restaurant_v2.json"
var checks: int = 0
var failures: int = 0
func _init() -> void:
	_test_shop_and_renovation()
	_test_service()
	_test_bonuses_and_limits()
	_test_validation()
	_test_mixed_rescue()
	_test_disk_recovery()
	print("%s: Tide Diver restaurant (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _new_progress() -> RefCounted:
	var p = Progress.new()
	p.persistence_enabled = false
	return p
func _openable() -> RefCounted:
	var p = _new_progress()
	p.coins = 210
	p.renovate("clean")
	p.renovate("kitchen")
	p.renovate("tables")
	return p
func _test_shop_and_renovation() -> void:
	var p = _new_progress()
	_check(p.coins == 0 and p.inventory_total() == 0 and not p.can_open(), "Fresh game is empty and closed")
	_check(not p.renovate("clean") and not p.renovate("missing"), "No money/unknown renovations rejected")
	p.inventory = {"orange":12,"blue":2,"lantern":1,"pearl":2,"chest":1}
	_check(p.sell("orange", 0) == 0 and p.sell("orange", -1) == 0 and p.sell("orange", 13) == 0 and p.sell("invalid", 1) == 0, "Invalid selling is atomic")
	_check(p.inventory.orange == 12 and p.coins == 0, "Rejected sale preserves inventory and money")
	_check(p.sell_valuables() == 146 and p.inventory.pearl == 0 and p.inventory.chest == 0 and p.inventory.orange == 12, "Valuables sale leaves cooking ingredients")
	_check(not p.renovate("kitchen") and p.coins == 146, "Renovation prerequisites enforced")
	_check(p.sell("orange", 12) == 216 and p.inventory.orange == 0, "Full fish sale pays canonical prices")
	_check(p.renovate("clean") and not p.renovate("clean"), "Renovation only purchased once")
	_check(p.renovate("kitchen") and p.renovate("tables") and p.coins == 152 and p.can_open(), "Minimum opening spend is exactly 210")
	_check(p.seats() == 2 and p.guest_limit() == 4 and p.patience() == 24.0, "Basic restaurant effects")
	_check(not p.begin_service({}) and not p.begin_service({"blue":3}) and not p.begin_service({"blue":-1}) and not p.begin_service({"blue":1.5}) and not p.begin_service({"pearl":1}), "Empty, excessive and malformed menus rejected")
func _test_service() -> void:
	var p = _openable()
	p.inventory.orange = 4
	p.inventory.blue = 2
	_check(p.begin_service({"orange":3,"blue":1}) and p.inventory.orange == 1 and p.inventory.blue == 1, "Menu reserves inventory once")
	_check(p.service_active and p.last_service_day == 1 and not p.begin_service({"orange":1}), "Active service cannot restart")
	p.coins = 1000
	_check(p.sell("orange",1) == 0 and p.sell_valuables() == 0 and not p.renovate("sign") and not p.buy_upgrade("tank"), "Shop and equipment transactions blocked during service")
	var cargo: Array = [{"id":"chest"}]
	p.complete_dive(cargo, false, 20)
	_check(cargo.size() == 1 and p.day == 1, "Dive settlement cannot occur during service")
	_check(p.allocate_dish() == "orange" and p.service_stock.orange == 2 and p.service_pending.size() == 1, "Customer allocation consumes one reserved portion")
	_check(p.record_served("orange") == 42 and p.coins == 1042 and p.total_served == 1, "Serving credits income and records exactly once")
	_check(p.record_served("orange") == 0 and p.record_served("invalid") == 0 and p.coins == 1042, "Duplicate/unallocated serving earns nothing")
	p.allocate_dish()
	p.record_lost("orange")
	p.record_lost("orange")
	_check(p.total_lost == 1 and p.coins == 1042, "Timeout consumes one pending order without payment")
	p.allocate_dish()
	var result: Dictionary = p.end_service(999)
	_check(result == {"earned":42,"served":1,"lost":2,"returned":1}, "Early close counts actual pending orders and returns unallocated stock")
	_check(p.inventory.orange == 1 and p.inventory.blue == 2 and p.restaurant_runs == 1 and p.total_lost == 2, "Reserved stock is conserved on close")
	_check(p.end_service() == result and p.restaurant_runs == 1 and p.inventory.blue == 2, "Repeated closing cannot duplicate returns or statistics")
	_check(not p.begin_service({"blue":1}), "One service per departure day")
	p.complete_dive([], false, 0)
	_check(p.begin_service({"blue":1}), "A new dive permits service next day")
	p.allocate_dish()
	_check(p.record_served("orange") == 0 and p.record_served("blue") == 72, "Only the allocated recipe can be served")
	p.end_service()
	_check(p.restaurant_income == 114 and p.total_served == 2 and p.restaurant_runs == 2, "Cumulative restaurant records persist across services")
func _test_bonuses_and_limits() -> void:
	var p = _openable()
	p.coins = 330
	_check(not p.renovate("decor"), "Decor requires sign")
	_check(p.renovate("sign") and p.renovate("expansion") and p.renovate("decor"), "Optional renovation costs total 330")
	_check(p.coins == 0 and p.seats() == 4 and p.guest_limit() == 8 and p.patience() == 32.0, "Optional effects modify seats, guests and patience")
	p.inventory.orange = 10
	p.begin_service({"orange":10})
	for i in range(8):
		_check(p.allocate_dish() == "orange" and p.record_served("orange") == 46, "Decor awards floored 10 percent tip")
	_check(p.allocate_dish().is_empty(), "Allocation respects maximum guest count")
	var result: Dictionary = p.end_service()
	_check(result.earned == 368 and result.returned == 2 and p.inventory.orange == 2, "Unneeded portions are returned after guest target")
func _test_validation() -> void:
	var p = _new_progress()
	p._apply_save_data({"inventory":{"orange":-5,"blue":2.2,"lantern":1.0e20,"pearl":"999","unknown":900}, "renovation":{"clean":false,"kitchen":true,"decor":true}, "restaurant_runs":-4,"last_service_day":9999})
	_check(p.inventory.orange == 0 and p.inventory.blue == 0 and p.inventory.lantern == 1000000 and p.inventory.pearl == 0 and not p.inventory.has("unknown"), "Inventory validates and bounds known integer quantities")
	_check(not p.renovation.kitchen and not p.renovation.decor and p.restaurant_runs == 0 and p.last_service_day == 1, "Corrupt progression flags respect prerequisites and limits")
	for path in ["C:/outside.json","user://outside.json","res://../outside.json","res://saves/../../outside.json","res://saves/C:/outside.json","res://scripts/main.gd"]:
		p.save_path = path
		_check(not p._allowed_save_path(), "Unsafe save path rejected: " + path)
	p.save_path = TEST_PATH
	_check(p._allowed_save_path(), "Test fixture save is allowed inside project")
func _write_fixture(contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/temp"))
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(contents)
	file.close()
func _clear_fixture() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
func _test_disk_recovery() -> void:
	_clear_fixture()
	_write_fixture(JSON.stringify({"version":1,"coins":367,"day":8,"tank_level":2,"bag_level":1,"spear_level":3,"total_fish":19,"best_depth":47.5}))
	var migrated = Progress.new()
	migrated.save_path = TEST_PATH
	migrated.load_game()
	_check(migrated.coins == 367 and migrated.day == 8 and migrated.tank_level == 2 and migrated.total_fish == 19 and migrated.best_depth == 47.5, "V1 migration preserves diving progress")
	_check(migrated.inventory_total() == 0 and not migrated.can_open() and migrated.restaurant_runs == 0, "V1 migration initializes restaurant fields")
	migrated.save_game()
	_check(JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH)).version == 4 and FileAccess.file_exists(TEST_PATH + ".bak"), "V4 saved with backup via temporary replacement")
	var p = _openable()
	p.persistence_enabled = true
	p.save_path = TEST_PATH
	p.inventory.orange = 4
	p.inventory.blue = 1
	p.begin_service({"orange":4,"blue":1})
	p.allocate_dish()
	p.record_served("orange")
	p.allocate_dish()
	var resumed = Progress.new()
	resumed.save_path = TEST_PATH
	resumed.load_game()
	_check(not resumed.service_active and resumed.inventory.orange == 2 and resumed.inventory.blue == 1 and resumed.coins == 42, "Interrupted service returns only unallocated ingredients")
	_check(resumed.total_served == 1 and resumed.total_lost == 1 and resumed.restaurant_runs == 1 and resumed.last_service_day == 1, "Recovery accounts pending losses and preserves earned income")
	_check(not resumed.recovery_notice.is_empty() and not resumed.begin_service({"orange":1}), "Recovery explains closure and preserves daily lock")
	var again = Progress.new()
	again.save_path = TEST_PATH
	again.load_game()
	_check(again.inventory.orange == 2 and again.coins == 42 and again.total_lost == 1 and again.restaurant_runs == 1, "Repeated load cannot duplicate recovery refunds")
	again.coins = 99
	again.save_game()
	_write_fixture("{broken json")
	var fallback = Progress.new()
	fallback.save_path = TEST_PATH
	fallback.load_game()
	_check(fallback.coins == 42 and not fallback.recovery_notice.is_empty(), "Damaged primary save falls back to prior valid backup")
	_clear_fixture()
	_write_fixture("[]")
	var fresh = Progress.new()
	fresh.save_path = TEST_PATH
	fresh.load_game()
	_check(fresh.coins == 0 and fresh.day == 1 and not fresh.recovery_notice.is_empty(), "Invalid save root with no backup uses defaults")
	_clear_fixture()


func _test_mixed_rescue() -> void:
	var p = _openable()
	p.inventory.blue = 3
	p.inventory.pearl = 2
	var before_inventory: Dictionary = p.inventory.duplicate(true)
	var before_renovation: Dictionary = p.renovation.duplicate(true)
	var result: Dictionary = p.complete_dive([{"id":"orange"},{"id":"pearl"},{"id":"chest"}], true, 24.0)
	_check(result.earned == 47 and p.coins == 47 and result.count == 3, "Mixed orange/pearl/chest rescue pays floor(136 * 35 / 100) = 47")
	_check(p.inventory == before_inventory and p.renovation == before_renovation and result.stored.is_empty(), "Mixed rescue preserves all shore inventory and completed renovations")



