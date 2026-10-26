extends SceneTree
## Pure in-memory progression checks; the real save is never read or written.
class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func save_game() -> void:
		saves += 1
var failures: int = 0
var checks: int = 0
func _init() -> void:
	_test_defaults_and_upgrades()
	_test_dive_settlement()
	_test_corrupt_save_data()
	print("%s: Tide Diver progression (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _test_defaults_and_upgrades() -> void:
	var p := MemoryProgression.new()
	_check(p.oxygen_max() == 100.0 and p.capacity() == 12 and p.spear_damage() == 1, "Initial equipment")
	_check(not p.buy_upgrade("tank") and not p.buy_upgrade("unknown"), "Unaffordable/unknown upgrades rejected")
	p.coins = 1000
	for level in range(3):
		_check(p.upgrade_cost("tank") == 80 * (level + 1) and p.buy_upgrade("tank"), "Increasing tank upgrade prices")
	_check(p.coins == 520 and p.oxygen_max() == 175.0, "Three tank upgrades cost 480")
	_check(p.upgrade_cost("tank") == -1 and not p.buy_upgrade("tank"), "Upgrade cap")
	_check(p.buy_upgrade("bag") and p.capacity() == 16, "Bag upgrade")
	_check(p.buy_upgrade("spear") and p.spear_damage() == 2, "Spear upgrade")
	_check(p.coins == 340 and p.saves == 5, "Upgrades save exactly once")
func _test_dive_settlement() -> void:
	var p := MemoryProgression.new()
	var cargo: Array = [{"id":"orange","value":999999}, {"kind":"pearl"}, {"name":"青背鱼","kind":"fish"}, {"id":"unknown","value":999999}, null]
	var result := p.complete_dive(cargo, false, 85.5)
	_check(result.earned == 0 and p.coins == 0 and result.count == 3, "Safe return stores valid goods without money")
	_check(result.stored == {"orange":1,"pearl":1,"blue":1} and p.inventory_total() == 3, "Legacy names/kinds and new IDs map to inventory")
	_check(cargo.is_empty() and p.total_fish == 2 and p.best_depth == 85.5 and p.day == 2, "Cargo consumed and dive statistics updated")
	p.complete_dive(cargo, false, 0.0)
	_check(p.inventory_total() == 3, "Consumed cargo cannot be stored twice")
	result = p.complete_dive([{"id":"chest","value":999999},{"id":"chest"}], true, 30.0)
	_check(result.earned == 63 and result.stored.is_empty() and p.coins == 63, "Rescue pays exact 35 percent of canonical prices")
	_check(p.inventory_total() == 3 and p.best_depth == 85.5, "Rescue preserves shore inventory and depth record")
	result = p.complete_dive([{"id":"invalid","kind":"chest"}], true, NAN)
	_check(result.count == 0 and result.earned == 0 and p.best_depth == 85.5, "Invalid explicit ID and NaN depth rejected")
func _test_corrupt_save_data() -> void:
	var p := MemoryProgression.new()
	p._apply_save_data(["wrong root"])
	_check(p.day == 1 and p.coins == 0, "Invalid save root ignored")
	p._apply_save_data({"coins":-3,"day":-5,"tank_level":900,"bag_level":-7,"spear_level":"bad","total_fish":1.0e20,"best_depth":-90})
	_check(p.coins == 0 and p.day == 1 and p.tank_level == 3 and p.bag_level == 0 and p.spear_level == 0, "Equipment and currency clamp")
	_check(p.total_fish == 999999999 and p.best_depth == 0.0, "Statistics bounded")
	p._apply_save_data({"coins":77.0,"day":4.0,"spear_level":2.0,"best_depth":123.4})
	_check(p.coins == 77 and p.day == 4 and p.spear_level == 2 and p.best_depth == 123.4, "JSON integer-valued floats supported")
	p._apply_save_data({"coins":INF,"day":null,"best_depth":NAN})
	_check(p.coins == 77 and p.day == 4 and p.best_depth == 123.4, "Invalid values preserve valid base state")
